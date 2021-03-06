package ccc.compute.server;

import ccc.compute.server.execution.routes.ServerCommands;
import ccc.compute.worker.WorkerStateManager;

import haxe.remoting.JsonRpc;
import haxe.DynamicAccess;

import js.node.Process;
import js.node.http.*;
import js.npm.docker.Docker;
import js.npm.express.Express;
import js.npm.express.Application;
import js.npm.express.Request;
import js.npm.express.Response;
import js.npm.JsonRpcExpressTools;
import js.npm.redis.RedisClient;

import minject.Injector;

import ccc.storage.*;

import util.RedisTools;
import util.DockerTools;

class ServerPaths
{
	public static function initAppPaths(injector :ServerState)
	{
		var app = Express.GetApplication();
		injector.map(Application).toValue(app);

		if (ServerConfig.ENABLE_REQUEST_LOGS) {
			app.use(Node.require('express-bunyan-logger')());
		}

		var cors = Node.require('cors')();
		app.use(cors);

		app.use(cast js.npm.bodyparser.BodyParser.json({limit: '250mb'}));

		var indexPage = new haxe.Template(sys.io.File.getContent('./web/index-template.html')).execute(ServerConfig);
		app.get('/', function(req, res) {
			res.send(indexPage);
		});

		app.get('/index.* ', function(req, res) {
			res.send(indexPage);
		});

		app.get('/version', function(req, res) {
			var versionBlob = ServerCommands.version();
			res.send(versionBlob.VERSION != null ? versionBlob.VERSION : versionBlob.git);
		});

		/**
		 * Adds bull dashboard to /dashboard
		 */
		QueueTools.addBullDashboard(injector);

		/**
		 * The function to test the overall health of the system.
		 * It runs jobs, so the actual jobs submitted to the queue
		 * need to be limited, otherwise in some cases they can pile
		 * up, bringing the system to a crawl.
		 */
		function test(req, res) {
			var monitorService = injector.getValue(ServiceMonitorRequest);
			monitorService.monitor(req.query)
				.then(function(result :ServiceMonitorRequestResult) {
					if (result.success) {
						res.json(result);
					} else {
						res.status(500).json(cast result);
					}
				}).catchError(function(err) {
					res.status(500).json(cast {error:err, success:false});
				});
		}

		app.get('/healthcheck', function(req, res :Response) {
			if (injector.getStatus() == ServerStartupState.Ready) {
				res.status(200).end();
			} else {
				res.status(503).end();
			}
		});

		app.get('/test', function(req, res) {
			test(req, res);
		});

		app.get('/test/cpu/:count/:duration', function(req, res :Response) {
			var count = Std.parseInt(req.params.count);
			var duration = Std.parseInt(req.params.duration);

			var routes :RpcRoutes = injector.getValue(RpcRoutes);

			var jobRequest :BasicBatchProcessRequest = {
				inputs: [],
				image: DOCKER_IMAGE_DEFAULT,
				parameters: {
					maxDuration: duration + 10,
					cpus: 1
				},
				cmd: ["sleep", '${duration}'],
				meta: {
					name: 'waittestjob'
				},
				turbo: true,
				wait: false,
			}

			var promises = [];
			for (i in 0...count) {
				promises.push(routes.submitJobJson(jobRequest));
			}

			Promise.whenAll(promises)
				.then(function(_) {
					res.json(cast {success:true});
				})
				.catchError(function(err :Dynamic) {
					res.status(500).json(err);
				});
		});

		app.get('/test/gpu/:count/:duration', function(req, res :Response) {
			var count = Std.parseInt(req.params.count);
			var duration = Std.parseInt(req.params.duration);

			var routes :RpcRoutes = injector.getValue(RpcRoutes);

			var jobRequest :BasicBatchProcessRequest = {
				inputs: [],
				image: 'nvidia/cuda',
				parameters: {
					maxDuration: duration + 10,
					gpu: 1,
				},
				cmd: ['/bin/sh', '-c', 'nvidia-smi && sleep ${duration}'],
				meta: {
					name: 'waittestjob'
				},
				turbo: true,
				wait: false,
			}

			if (ServerConfig.DISABLE_NVIDIA_RUNTIME) {
				jobRequest.image = DOCKER_IMAGE_DEFAULT;
				jobRequest.cmd = ["echo", "'nvidia disabled'"];
			}

			var promises = [];
			for (i in 0...count) {
				promises.push(routes.submitJobJson(jobRequest));
			}

			Promise.whenAll(promises)
				.then(function(_) {
					res.json(cast {success:true});
				})
				.catchError(function(err :Dynamic) {
					res.status(500).json(err);
				});
		});

		app.get('/test/gpu', function(req, res :Response) {

			var routes :RpcRoutes = injector.getValue(RpcRoutes);

			var jobRequest :BatchProcessRequestTurboV2 = {
				inputs: [],
				image: 'nvidia/cuda',
				parameters: {
					maxDuration: 100,
					gpu: 1,
				},
				command: ['nvidia-smi'],
			}

			if (ServerConfig.DISABLE_NVIDIA_RUNTIME) {
				jobRequest.image = DOCKER_IMAGE_DEFAULT;
				jobRequest.command = ["echo", "'nvidia disabled'"];
			}

			routes.submitTurboJobJsonV2(jobRequest)
				.then(function(job) {
					res.json(job);
				})
				.catchError(function(err :Dynamic) {
					res.status(500).json(err);
				});
		});

		/**
		 * Used in tests to check for loading URL inputs
		 */
		app.get('/mirrorfile/:content', function(req, res) {
			res.send(req.params.content);
		});

		app.get('/check', function(req, res) {
			test(req, res);
		});

		app.get('/version_extra', function(req, res) {
			var versionBlob = ServerCommands.version();
			res.send(Json.stringify(versionBlob));
		});

		//Check if server is listening
		app.get(Constants.SERVER_PATH_CHECKS, function(req, res) {
			res.send(Constants.SERVER_PATH_CHECKS_OK);
		});
		//Check if server is listening
		app.get(Constants.SERVER_PATH_STATUS, function(req, res) {
			res.send('{"status":"${injector.getStatus()}"}');
		});

		//Check if server is ready
		app.get(SERVER_PATH_READY, cast function(req, res) {
			if (injector.getStatus() == ServerStartupState.Ready) {
				res.status(200).end();
			} else {
				res.status(503).end();
			}
		});

		//Check if server is ready
		app.get(SERVER_PATH_WAIT, cast function(req, res) {
			function check() {
				if (injector.getStatus() == ServerStartupState.Ready) {
					res.status(200).end();
					return true;
				} else {
					return false;
				}
			}
			var ended = false;
			req.once(ReadableEvent.Close, function() {
				ended = true;
			});
			var poll;
			poll = function() {
				if (!check() && !ended) {
					Node.setTimeout(poll, 1000);
				}
			}
			poll();
		});

		//Check if server is listening
		app.get('/jobcount', function(req, res :Response) {
			if (injector.hasMapping(WorkerStateManager)) {
				var wc :WorkerStateManager = injector.getValue(WorkerStateManager);
				wc.jobCount()
					.then(function(count) {
						res.json({count:count});
					})
					.catchError(function(err) {
						res.status(500).json(cast {error:err});
					});
			} else {
				res.json({count:0});
			}
		});

		//Quick summary of worker jobs counts for scaling control.
		app.get('/worker-jobs', function(req, res :Response) {
			if (injector.hasMapping(ServerRedisClient)) {
				Jobs.getAllWorkerJobs()
					.pipe(function(result) {
						return JobStateTools.getJobsWithStatus(JobStatus.Pending)
							.then(function(jobIds) {
								res.json({
									waiting:jobIds,
									workers:result
								});
							});
					})
					.catchError(function(err) {
						res.status(500).json(cast {error:err});
					});
			} else {
				res.json({});
			}
		});
	}
}