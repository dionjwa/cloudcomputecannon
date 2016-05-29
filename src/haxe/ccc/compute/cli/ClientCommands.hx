package ccc.compute.cli;

import ccc.compute.client.ClientCompute;
import ccc.compute.Definitions;
import ccc.compute.Definitions.Constants.*;
import ccc.compute.JobTools;
import ccc.compute.InitConfigTools;
import ccc.compute.ServiceBatchCompute;
import ccc.compute.workers.WorkerProviderTools;
import ccc.compute.server.ProviderTools;
import ccc.compute.server.ProviderTools.*;
import ccc.compute.cli.CliTools.*;

import js.Node;
import js.node.http.*;
import js.node.ChildProcess;
import js.node.Path;
import js.node.stream.Readable;
import js.node.Fs;
import js.npm.HttpPromises;
import js.npm.FsExtended;
import js.npm.Request;

import haxe.Json;

import promhx.Promise;
import promhx.RequestPromises;
import promhx.deferred.DeferredPromise;

import t9.abstracts.net.*;

import yaml.Yaml;

import util.SshTools;

using ccc.compute.ComputeTools;
using promhx.PromiseTools;
using StringTools;
using DateTools;
using Lambda;

enum ClientResult {
	Websocket;
}

typedef ClientJobRecord = {
	var jobId :JobId;
	var jobRequest :BasicBatchProcessRequest;
}

typedef JobWaitingStatus = {
	var jobId :JobId;
	var status :String;
	@:optional var error :Dynamic;
	@:optional var job : JobDataBlob;
}

@:enum
abstract DevTestCommand(String) to String from String {
	var Longjob = 'longjob';
}

typedef SubmissionDataBlob = {
	var jobId :JobId;
}

/**
 * "Remote" methods that run locally
 */
class ClientCommands
{
	@rpc({
		alias:'devtest',
		doc:'Various convenience functions for dev testing',
		args:{
			'command':{doc: 'Output is JSON'}
		}
	})
	public static function devtest(command :String) :Promise<CLIResult>
	{
		var devCommand :DevTestCommand = command;
		return switch(command) {
			case Longjob:
				runclient(['sleep', '500'], 'ubuntu')
					.thenVal(CLIResult.Success);
			default:
				log('Unknown command=$command');
				Promise.promise(CLIResult.PrintHelpExit1);
		}
	}

	@rpc({
		alias:'run',
		doc:'Run docker job(s) on the compute provider. Example:\n cloudcannon run --image=elyase/staticpython --command=\'["python", "-c", "print(\'Hello World!\')"]\'\nReturns the jobId',
		args:{
			command: {doc:'Command to run in the docker container, specified as a JSON String Array, e.g. \'["echo", "foo"]\''},
			directory: {doc: 'Path to directory containing the job definition', short:'d'},
			image: {doc: 'Docker image name [ubuntu:14.04]', short: 'm'},
			count: {doc: 'Number of job repeats [1]', short: 'n'},
			input: {doc:'Input values (decoded into JSON values) [input]. E.g.: --input foo1=SomeString --input foo2=2 --input foo3="[1,2,3,4]". ', short:'i'},
			inputfile: {doc:'Input files [inputfile]. E.g. --inputfile foo1=/home/user1/Desktop/test.jpg" --input foo2=/home/me/myserver/myfile.txt ', short:'f'},
			inputurl: {doc:'Input urls (downloaded from the server) [inputurl]. E.g. --input foo1=http://someserver/test.jpg --input foo2=http://myserver/myfile', short:'u'},
			results: {doc: 'Results directory [./<results_dir>/<date string>__<jobId>/]. The contents of that folder will have an inputs/ and outputs/ directories. '},
			// json: {doc: 'Output in JSON.'}
		}
	})
	public static function runclient(
		command :Array<String>,
		?image :String,
		?directory :String,
		?input :Array<String>,
		?inputfile :Array<String>,
		?inputurl :Array<String>,
		?count :Int = 1,
		?results :String
		// ?json :Bool = true
		// ) :Promise<ClientJobRecord>
		)
	{
		var jobParams :BasicBatchProcessRequest = {
			image: image != null ? image : Constants.DOCKER_IMAGE_DEFAULT,
			cmd: command,//command != null ? Json.parse(command) : null,
			parameters: {cpus:1, maxDuration:60*1000*10},
			inputs: [],
		};
		return runInternal(jobParams, input, inputfile, inputurl, count, results);
	}

	@rpc({
		alias:'runjson',
		doc:'Run docker job(s) on the compute provider. Example:\n cloudcannon run --image=elyase/staticpython --command=\'["python", "-c", "print(\'Hello World!\')"]\'',
		args:{
			jsonfile: {doc: 'Path to json file with the job spec'},
			count: {doc: 'Number of job repeats [1]', short: 'n'},
			input: {doc:'Input files/values/urls [input]. Formats: --input "foo1=@/home/user1/Desktop/test.jpg" --input "foo2=@http://myserver/myfile --input "foo3=4". ', short:'i'},
			inputfile: {doc:'Input files/values/urls [input]. Formats: --input "foo1=@/home/user1/Desktop/test.jpg" --input "foo2=@http://myserver/myfile --input "foo3=4". ', short:'i'},
			results: {doc: 'Results directory [./<results_dir>/<date string>__<jobId>/]. The contents of that folder will have an inputs/ and outputs/ directories. '},
			// json: {doc: 'Output in JSON [true].'}
		}
	})
	public static function runJson(
		jsonfile: String,
		?input :Array<String>,
		?inputfile :Array<String>,
		?inputurl :Array<String>,
		?count :Int = 1,
		?results: String
		)
	{
		var jobParams :BasicBatchProcessRequest = Json.parse(Fs.readFileSync(jsonfile, 'utf8'));
		return runInternal(jobParams, input, inputfile, inputurl, count, results);
	}

	static function runInternal(
		jobParams: BasicBatchProcessRequest,
		?input :Array<String>,
		?inputfile :Array<String>,
		?inputurl :Array<String>,
		?count :Int = 1,
		?results: String,
		?json :Bool = true) :Promise<SubmissionDataBlob>
	{
		var dateString = Date.now().format("%Y-%m-%d");
		var resultsBaseDir = results != null ? results : 'results';

		//Construct the inputs
		var inputs :Array<ComputeInputSource> = [];
		if (input != null) {
			for (inputItem in input) {
				var tokens = inputItem.split('=');
				var inputName = tokens.shift();
				inputs.push({
					type: InputSource.InputInline,
					value: tokens.join('='),
					name: inputName
				});
			}
		}
		if (inputurl != null) {
			for (url in inputurl) {
				// trace('url=${url}');
				var tokens = url.split('=');
				var inputName = tokens.shift();
				var inputUrl = tokens.join('=');
				// trace('Requesting $inputUrl');
				inputs.push({
					type: InputSource.InputUrl,
					value: inputUrl,
					name: inputName
				});
			}
		}

		jobParams.inputs = jobParams.inputs == null ? inputs :jobParams.inputs.concat(inputs);

		var inputStreams = {};
		if (inputfile != null) {
			for (file in inputfile) {
				var tokens = file.split('=');
				var inputName = tokens.shift();
				var inputPath = tokens.join('=');
				var stat = Fs.statSync(inputPath);
				if (!stat.isFile()) {
					throw('ERROR no file $inputPath');
				}
				// trace('Streaming local $inputPath');
				Reflect.setField(inputStreams, inputName, Fs.createReadStream(inputPath, {encoding:'binary'}));
			}
		}

		// trace('jobParams=${jobParams}');
		return getServerAddress()
			.pipe(function(address) {
				return ClientCompute.postJob(address, jobParams, inputStreams)
					.then(function(result) {
						// trace('result=${result}');
						//Write the client job file
						var clientJobFileDirPath = Path.join(resultsBaseDir, '${dateString}__${result.jobId}');
						FsExtended.ensureDirSync(clientJobFileDirPath);
						var clientJobFilePath = Path.join(clientJobFileDirPath, Constants.SUBMITTED_JOB_RECORD_FILE);
						var submissionData :SubmissionDataBlob = {
							jobId: result.jobId,
							// jobRequest: jobParams
						}
						FsExtended.writeFileSync(clientJobFilePath, Json.stringify(submissionData, null, '\t'));
						var stdout = json ? Json.stringify(submissionData, null, '\t') : result.jobId;
						log(stdout);
						return submissionData;
					})
					.errorPipe(function(err) {
						trace(err);
						return Promise.promise(null);
					});
			});
	}

	@rpc({
		alias:'image-build',
		doc:'Build a docker image from a context (directory containing a Dockerfile).',
	})
	public static function buildDockerImage(path :String, repository :String) :Promise<CLIResult>
	{
		trace('buildDockerImage path=$path repository=$repository');
		var host = getHost();
		var tarStream = js.npm.TarFs.pack(path);
		var url = 'http://${host}$SERVER_URL_API_DOCKER_IMAGE_BUILD/$repository';
		function onError(err) {
			Log.error(err);
			trace(err);
		}
		tarStream.on(ReadableEvent.Error, onError);
		return RequestPromises.postStreams(url, tarStream)
			.pipe(function(response) {
				var responsePromise = new DeferredPromise<CLIResult>();
				response.on(ReadableEvent.Error, onError);
				response.once(ReadableEvent.End, function() {
					responsePromise.resolve(CLIResult.Success);
				});
				response.pipe(Node.process.stdout);
				return responsePromise.boundPromise;
			})
			.errorPipe(function(err) {
				trace(err);
				return Promise.promise(CLIResult.ExitCode(-1));
			});
	}

	@rpc({
		alias:'wait',
		doc:'Wait on jobs. Defaults to all currently running jobs, or list jobs with wait <jobId1> <jobId2> ... <jobIdn>',
	})
	public static function wait(job :Array<String>) :Promise<CLIResult>
	{
		var host = getHost();
		var promises = [];
		var clientProxy = getProxy(host.rpcUrl());
		return Promise.promise(true)
			.pipe(function(_) {
				if (job == null) {
					return clientProxy.jobs();
				} else {
					return Promise.promise(job);
				}
			})
			.pipe(function(jobIds) {
				var promises = jobIds.map(function(jobId) {
					return function() return ClientCompute.getJobResult(host, jobId);
				});
				return PromiseTools.chainPipePromises(promises)
					.then(function(jobResults) {
						trace('jobResults=${jobResults}');
						return CLIResult.Success;
					});
			});
	}

	static function waitInternal(?job :Array<JobId>) :Promise<Array<JobWaitingStatus>>
	{
		trace('waitInternal is not yet implemented');
		return Promise.promise([]);
		//Gather all job.json files in the base dir
		// var jobFiles = FsExtended.listFilesSync(js.Node.process.cwd(), {recursive:true, filter:function(itemPath :String, stat) return itemPath.endsWith(Constants.SUBMITTED_JOB_RECORD_FILE)});
		// return getServerAddress()
		// 	.pipe(function(address) {
		// 		var promises :Array<Promise<JobWaitingStatus>>= [];
		// 		for (jobFile in jobFiles) {
		// 			var submissionData :ClientJobRecord = null;
		// 			try {
		// 				submissionData = Json.parse(FsExtended.readFileSync(jobFile, {}));
		// 			} catch(err :Dynamic) {
		// 				trace(err);
		// 				continue;
		// 			}

		// 			var jobId :JobId = submissionData.jobId;
		// 			if (job != null && !job.has(jobId)) {
		// 				continue;
		// 			}
		// 			var baseResultsDir = Path.dirname(jobFile);
		// 			var resultsJsonFile = Path.join(baseResultsDir, JobTools.RESULTS_JSON_FILE);

		// 			var resultsJsonFileExists = FsExtended.existsSync(resultsJsonFile);
		// 			if (resultsJsonFileExists) {
		// 				var result :JobWaitingStatus = {jobId:jobId, status:'finished', job:null};
		// 				promises.push(Promise.promise(result));
		// 			} else {
		// 				//Check if the results have been downloaded locally
		// 				var outputsPath = submissionData.jobRequest.outputsPath;

		// 				var p = ClientCompute.getJobResult(address, jobId)
		// 					.then(function(jobResult) {
		// 						FsExtended.writeFileSync(resultsJsonFile, jsonString(jobResult));
		// 						//TODO: download output/input files
		// 						var result :JobWaitingStatus = {jobId:jobId, status:'finished just now', job:jobResult};
		// 						return result;
		// 					})
		// 					.errorPipe(function(err) {
		// 						trace('err=${err}');
		// 						var result :JobWaitingStatus = {jobId:jobId, status:'error', error:err, job:null};
		// 						return Promise.promise(result);
		// 					});
		// 				promises.push(p);
		// 			}
		// 		}
		// 		return Promise.whenAll(promises);
		// 	});
	}

	// @rpc({
	// 	alias:'info',
	// 	doc:'Info on the current setup',
	// 	args:{
	// 		'json':{doc: 'Output is JSON', short: 'j'}
	// 	}
	// })
	// public static function info(?json :Bool = true) :Promise<Bool>
	// {
	// 	var result = {
	// 		server_connection_file: null,
	// 		server_running: false
	// 	}

	// 	result.server_connection_file = CliTools.findExistingServerConfigPath();
	// 	return Promise.promise(true)
	// 		.pipe(function(_) {
	// 			if (result.server_connection_file != null) {
	// 				var path = result.server_connection_file;
	// 				result.server_connection_file += '/$LOCAL_CONFIG_DIR/$SERVER_CONNECTION_FILE';
	// 				var connectionBlob = readServerConfig(path);
	// 				var host :Host = getHostFromServerConfig(connectionBlob.data);
	// 				return ProviderTools.serverCheck(host)
	// 					.then(function(ok) {
	// 						result.server_running = ok;
	// 						return true;
	// 					});
	// 			} else {
	// 				return Promise.promise(true);
	// 			}
	// 		})
	// 		.then(function(_) {
	// 			log(Json.stringify(result, null, '\t'));
	// 			return true;
	// 		});
	// }

	@rpc({
		alias:'shutdown',
		doc:'Shut down the remote server',
	})
	public static function shutdown() :Promise<CLIResult>
	{
		var path = Node.process.cwd();
		if (!isServerConnection(path)) {
			log('No server configuration @${buildServerConnectionPath(path)}. Nothing to shut down.');
			return Promise.promise(CLIResult.Success);
		}
		var serverBlob :ServerConnectionBlob = readServerConnection(path);
		var provider = WorkerProviderTools.getProvider(serverBlob.provider.providers[0]);
		trace('shutting down server ${serverBlob.server.id}');
		Log.warn('TODO: properly clean up workers');
		return provider.destroyInstance(serverBlob.server.id)
			.then(function(_) {
				trace('deleting connection file');
				deleteServerConnection(path);
				return CLIResult.Success;
			});
	}

	@rpc({
		alias:'server-stop',
		doc:'Stop down the remote server',
	})
	public static function stopServer() :Promise<CLIResult>
	{
		var path = Node.process.cwd();
		if (!isServerConnection(path)) {
			log('No server configuration @${buildServerConnectionPath(path)}. Nothing to shut down.');
			return Promise.promise(CLIResult.Success);
		}
		var serverBlob :ServerConnectionBlob = readServerConnection(path);
		return ProviderTools.stopServer(serverBlob)
			.thenVal(CLIResult.Success);
	}

	@rpc({
		alias:'update-config',
		doc:'Update the server configuration json file.',
		args:{
			'config':{doc: '<Path to server config yaml/json file>'}
		}
	})
	public static function updateServerConfig(config :String) :Promise<CLIResult>
	{
		var path = Node.process.cwd();
		if (config != null && !FsExtended.existsSync(config)) {
			log('Missing configuration file: $config');
			return Promise.promise(CLIResult.PrintHelpExit1);
		}

		if (!isServerConnection(path)) {
			log('No existing installation @${buildServerConnectionPath(path)}. Have you run "$CLI_COMMAND install"?');
			return Promise.promise(CLIResult.PrintHelpExit1);
		}

		var serverBlob :ServerConnectionBlob = readServerConnection(path);

		var serverConfig = InitConfigTools.getConfigFromFile(config);
		serverBlob.provider = serverConfig;
		writeServerConnection(serverBlob, path);

		return Promise.promise(CLIResult.Success);
	}

	@rpc({
		alias:'install',
		doc:'Install the cloudcomputecannon server on a provider:\n  cloudcannon install <vagrant | Path to server config yaml file>',
		args:{
			'config':{doc: '<Path to server config yaml file>'}
		}
	})
	public static function install(config :String, ?force :Bool = false, ?uploadOnly :Bool = false) :Promise<CLIResult>
	{
		var path = Node.process.cwd();
		// var existingServerConnectionJsonPath = Path.join(path, LOCAL_CONFIG_DIR, SERVER_CONNECTION_FILE);
		// trace('existingServerConnectionJsonPath=${existingServerConnectionJsonPath}');
		// var existingServerConnectionJsonFileExists = FsExtended.existsSync(existingServerConnectionJsonPath);
		// trace('existingServerConnectionJsonFileExists=${existingServerConnectionJsonFileExists}');

		//Missing config file check
		if (config != null && !FsExtended.existsSync(config)) {
			log('Missing configuration file: $config');
			return Promise.promise(CLIResult.PrintHelpExit1);
		}

		if (config != null && isServerConnection(path)) {
			log('Existing installation @${buildServerConnectionPath(path)}. If there is an existing installation, you cannot override with a new installation without first removing the current installation.');
			return Promise.promise(CLIResult.PrintHelpExit1);
		}

		// //We cannot have two configurations override.
		// if (config != null && FsExtended.existsSync(config) && existingServerConnectionJsonFileExists) {
		// 	log('Existing config, cannot override. Shut down the existing server. File=${Path.join(path, LOCAL_CONFIG_DIR, SERVER_CONNECTION_FILE)}');
		// 	return Promise.promise(false);
		// }

		// var serverConfig :ServiceConfiguration = null;

		return Promise.promise(true)
			.pipe(function(_) {
				if (isServerConnection(path)) {
					//Perform tests on the existing server
					var serverBlob :ServerConnectionBlob = readServerConnection(path);
					return Promise.promise(serverBlob);
				} else {
					//Just create the server instance.
					//It doesn't validate or check the running containers, that is the next step
					var serverConfig = InitConfigTools.getConfigFromFile(config);
					var providerConfig = serverConfig.providers[0];
					return ProviderTools.createServerInstance(providerConfig)
						.then(function(instanceDef) {
							var serverBlob :ServerConnectionBlob = {server:instanceDef, provider:serverConfig};
							writeServerConnection(serverBlob, path);
							return serverBlob;
						});
				}
			})
			//Don't assume anything is working except ssh/docker connections.
			.pipe(function(serverBlob) {
				// trace('serverBlob=${serverBlob}');
				return ProviderTools.installServer(serverBlob, force, uploadOnly);
				// return ProviderTools.copyFilesForRemoteServer(serverBlob);
			})
			// .pipe(function(_) {
			// 	// trace('checking server now');
			// 	return servercheck();
			// })
			.thenVal(CLIResult.Success);


		// return Promise.promise(true)
		// 	.pipe(function(_) {
		// 		if (vagrant) {
		// 			var serverConfig :ServiceConfiguration = InitConfigTools.parseConfig(Resource.getString('ServerConfigVagrant'));
		// 			return Promise.promise(null);
		// 		} else {
		// 			//Some more complex checking here in case previous installs failed or containers have gone down.
		// 		}
		// 	})
		// 	//We have a bare CoreOS instance now
		


		
		// var serverConfig :ServiceConfiguration = if (vagrant) {
		// 	trace('haxe.Resource.getString("ServerConfigVagrant")=${haxe.Resource.getString("ServerConfigVagrant")}');
		// 	InitConfigTools.parseConfig(haxe.Resource.getString('ServerConfigVagrant'));
		// } else if (config == null) {
		// 	InitConfigTools.getDefaultConfig();
		// } else {
		// 	InitConfigTools.getConfigFromFile(config);
		// }
		// trace('serverConfig=${serverConfig}');
		// return ProviderTools.buildRemoteServer(serverConfig.providers[0])
		// 	.then(function(serverBlob) {
		// 		trace('serverBlob=${serverBlob}');
		// 		// var serverblob :ServerConnectionBlob = {server:instanceDef};
		// 		// CliTools.writeServerConnection(serverblob);
		// 		return true;
		// 	});
		// return Promise.promise(true);
	}

	@rpc({
		alias:'config',
		doc:'Print out the current configuration. Defaults to YAML output.',
		args:{
			'json':{doc: 'Output is JSON', short: 'j'}
		}
	})
	public static function config(?json :Bool = false) :Promise<CLIResult>
	{
		var config = getConfiguration();
		if (json) {
			log(jsonString(config));
		} else {
			log(Yaml.render(config));
		}
		return Promise.promise(CLIResult.Success);
	}

	@rpc({
		alias:'server-check',
		doc:'Checks the server via SSH and the HTTP API'
	})
	public static function servercheck() :Promise<CLIResult>
	{
		var configPath = findExistingServerConfigPath();
		if (configPath == null) {
			log(Json.stringify({error:'Missing server configuration in this directory. Have you run "$CLI_COMMAND install" '}));
			return Promise.promise(CLIResult.PrintHelpExit1);
		}
		var connection = readServerConnection(configPath);
		if (connection == null) {
			log(Json.stringify({error:'Missing server configuration in this directory. Have you run "$CLI_COMMAND install" '}));
			return Promise.promise(CLIResult.PrintHelpExit1);
		}
		return ProviderTools.serverCheck(connection.server)
			.then(function(result) {
				result.connection_file_path = buildServerConnectionPath(configPath);
				return result;
			})
			.then(function(result) {
				log(Json.stringify(result, null, '\t'));
				return CLIResult.Success;
			});
	}

	@rpc({
		alias:'server-ping',
		doc:'Checks the server API'
	})
	public static function serverPing() :Promise<CLIResult>
	{
		var host = getHost();
		var url = 'http://$host/checks';
		return HttpPromises.get(url)
			.then(function(out) {
				var ok = out.trim() == SERVER_PATH_CHECKS_OK;
				log(ok ? 'OK' : 'FAIL');
				return ok ? CLIResult.Success : CLIResult.ExitCode(1);
			})
			.errorPipe(function(err) {
				log(Json.stringify({error:err}));
				return Promise.promise(CLIResult.ExitCode(1));
			});
	}

	@rpc({
		alias:'job-download',
		doc:'Given a jobId, downloads job results and data',
		args:{
			'job':{doc: 'JobId of the job to download'},
			'path':{doc: 'Path to put the results files. Defaults to ./<jobId>'}
		}
	})
	public static function jobDownload(job :JobId, ?path :String = null, ?includeInputs :Bool = false) :Promise<CLIResult>
	{
		if (job == null) {
			warn('Missing job argument');
			return Promise.promise(CLIResult.PrintHelpExit1);
		}
		// trace('jobDownload job=${job} path=${path} includeInputs=${includeInputs}');
		var downloadPath = path == null ? Path.join(Node.process.cwd(), job) : path;
		// trace('downloadPath=${downloadPath}');
		var outputsPath = Path.join(downloadPath, DIRECTORY_OUTPUTS);
		var inputsPath = Path.join(downloadPath, DIRECTORY_INPUTS);
		var host = getHost();
		// return Promise.promise(CLIResult.Success);
		// FsExtended.ensureDirSync(downloadPath);
		return doJobCommand(job, JobCLICommand.Result)
			.pipe(function(jobResult :JobResult) {
				if (jobResult == null) {
					warn('No job id: $job');
					return Promise.promise(CLIResult.ExitCode(1));
				}
				var localStorage = ccc.storage.ServiceStorageLocalFileSystem.getService(downloadPath);
				var promises = [];
				for (source in [STDOUT_FILE, STDERR_FILE, 'resultJson']) {
					var localPath = source == 'resultJson' ? 'result.json' : source;
					var sourceUrl :String = Reflect.field(jobResult, source);
					if (!sourceUrl.startsWith('http')) {
						sourceUrl = 'http://$host/$sourceUrl';
					}
					var fp = function() {
						log('Downloading $sourceUrl => $downloadPath/$localPath');
						return localStorage.writeFile(localPath, Request.get(sourceUrl))
							.errorPipe(function(err) {
								try {
									FsExtended.deleteFileSync(Path.join(downloadPath, localPath));
								} catch(deleteFileErr :Dynamic) {
									//Ignored
								}
								return Promise.promise(true);
							});
					}
					promises.push(fp);
				}
				var outputStorage = ccc.storage.ServiceStorageLocalFileSystem.getService(outputsPath);
				for (source in jobResult.outputs) {
					var localPath = source;
					var remotePath = Path.join(jobResult.outputsBaseUrl, source);
					if (!remotePath.startsWith('http')) {
						remotePath = 'http://$host/$remotePath';
					}
					var p = function() {
						log('Downloading $remotePath => $outputsPath/$localPath');
						return outputStorage.writeFile(localPath, Request.get(remotePath))
							.errorPipe(function(err) {
								try {
									FsExtended.deleteFileSync(Path.join(outputsPath, localPath));
								} catch(deleteFileErr :Dynamic) {
									//Ignored
								}
								return Promise.promise(true);
							});
					}
					promises.push(p);
				}
				if (includeInputs) {
					var inputStorage = ccc.storage.ServiceStorageLocalFileSystem.getService(inputsPath);
					for (source in jobResult.inputs) {
						var localPath = source;
						var remotePath = Path.join(jobResult.inputsBaseUrl, source);
						if (!remotePath.startsWith('http')) {
							remotePath = 'http://$host/$remotePath';
						}
						var p = function() {
							log('Downloading $remotePath => $inputsPath/$localPath');
							return inputStorage.writeFile(localPath, Request.get(remotePath))
								.errorPipe(function(err) {
									try {
										FsExtended.deleteFileSync(Path.join(inputsPath, localPath));
									} catch(deleteFileErr :Dynamic) {
										//Ignored
									}
									return Promise.promise(true);
								});
						}
						promises.push(p);
					}
				}

				return PromiseTools.chainPipePromises(promises)
				// return Promise.whenAll(promises.map(function(f) return f()))
					.thenVal(CLIResult.Success);
			});
	}

	@rpc({
		alias:'test',
		doc:'Test a simple job with a cloud-compute-cannon server'
	})
	public static function test() :Promise<CLIResult>
	{
		var rand = Std.string(Std.int(Math.random() * 1000000));
		var stdoutText = 'HelloWorld$rand';
		var outputText = 'output$rand';
		var outputFile = 'output1';
		var inputFile = 'input1';
		var command = ["python", "-c", 'data = open("/$DIRECTORY_INPUTS/$inputFile","r").read()\nprint(data)\nopen("/$DIRECTORY_OUTPUTS/$outputFile", "w").write(data)'];
		var image = 'elyase/staticpython';

		var jobParams :BasicBatchProcessRequest = {
			image: image,
			cmd: command,
			parameters: {cpus:1, maxDuration:60*1000*10},
			inputs: [],
			outputsPath: 'someTestOutputPath/outputs',
			inputsPath: 'someTestInputPath/inputs'
		};
		return runInternal(jobParams, ['$inputFile=input1$rand'], [], [], 1, './tmp/results')
		// return runclient(command, image, null, ['input1=input1$rand'], 1, './tmp/results')
			.pipe(function(submissionData :SubmissionDataBlob) {
				if (submissionData != null) {
					var jobId = submissionData.jobId;
					return waitInternal([jobId])
						.pipe(function(out) {
							if (out.length > 0) {
								var jobResult = out[0].job;
								if (jobResult != null && jobResult.exitCode == 0) {
									return getServerAddress()
										.pipe(function(address) {
											return HttpPromises.get('http://' + jobResult.stdout)
												.then(function(stdout) {
													log('stdout=${stdout.trim()}');
													Assert.that(stdout.trim() == stdoutText);
													return true;
												});
										});
								} else {
									log('jobResult is null ');
									return Promise.promise(false);
								}
							} else {
								log('No waiting jobs');
								return Promise.promise(false);
							}
						});
				} else {
					return Promise.promise(false);
				}
			})
			.then(function(success) {
				if (!success) {
					//Until waiting is implemented
					// log('Failure');
				}
				return success ? CLIResult.Success : CLIResult.ExitCode(1);
			})
			.errorPipe(function(err) {
				log(err);
				return Promise.promise(CLIResult.ExitCode(1));
			});
	}

	@rpc({
		alias:'job-run-local',
		doc:'Download job inputs and run locally. Useful for replicating problematic jobs.',
		args:{
			'path':{doc: 'Base path for the job inputs/outputs/results'}
		}
	})
	public static function runRemoteJobLocally(job :JobId, ?path :String) :Promise<CLIResult>
	{
		var host = getHost();
		var downloadPath = path == null ? Path.join(Node.process.cwd(), job) : path;
		downloadPath = Path.normalize(downloadPath);
		var inputsPath = Path.join(downloadPath, DIRECTORY_INPUTS);
		var outputsPath = Path.join(downloadPath, DIRECTORY_OUTPUTS);
		return doJobCommand(job, JobCLICommand.Definition)
			.pipe(function(jobDef :DockerJobDefinition) {
				trace('${jobDef}');
				FsExtended.deleteDirSync(outputsPath);
				FsExtended.ensureDirSync(outputsPath);
				var localStorage = ccc.storage.ServiceStorageLocalFileSystem.getService(downloadPath);
				var promises = [];
				//Write inputs
				var inputsStorage = ccc.storage.ServiceStorageLocalFileSystem.getService(inputsPath);
				for (source in jobDef.inputs) {
					var localPath = source;
					var remotePath = 'http://' + host + '/' + jobDef.inputsPath + source;
					var p = inputsStorage.writeFile(localPath, Request.get(remotePath))
						.errorPipe(function(err) {
							Node.process.stderr.write(err + '\n');
							return Promise.promise(true);
						});
					promises.push(p);
				}
				return Promise.whenAll(promises)
					.pipe(function(_) {
						var promise = new DeferredPromise();
						var dockerCommand = ['run', '--rm', '-v', inputsPath + ':/' + DIRECTORY_INPUTS, '-v', outputsPath + ':/' + DIRECTORY_OUTPUTS, jobDef.image.value];
						var dockerCommandForConsole = dockerCommand.concat(jobDef.command.map(function(s) return '"$s"'));
						dockerCommand = dockerCommand.concat(jobDef.command);
						trace('Command to replicate the job:\n\ndocker ${dockerCommandForConsole.join(' ')}\n');
						var process = ChildProcess.spawn('docker', dockerCommand);
						var stdout = '';
						var stderr = '';
						process.stdout.on(ReadableEvent.Data, function(data) {
							stdout += data + '\n';
							// console.log('stdout: ${data}');
						});
						process.stderr.on(ReadableEvent.Data, function(data) {
							stderr += data + '\n';
							// console.error('stderr: ${data}');
						});
						process.on('close', function(code) {
							console.log('EXIT CODE: ${code}');
							console.log('STDOUT:\n\n$stdout\n');
							console.log('STDERR:\n\n$stderr\n');
							promise.resolve(true);
						});
						return promise.boundPromise;
					})
					.thenVal(CLIResult.Success);
			});
	}

	@rpc({
		alias:'ensureServerInstanceOLD',
		doc:'Install the cloudcomputecannon server on a provider:\n  cloudcannon install <vagrant | Path to server config yaml file>',
		args:{
			'config':{doc: '<vagrant | Path to server config yaml file>'}
		}
	})
	public static function ensureServerInstanceOLD(?config :String = 'foooooooooooooo') :Promise<InstanceDefinition>
	{
		return null;
		// var path = Node.process.cwd();
		// var serverConnectionPath = Path.join(path, LOCAL_CONFIG_DIR, SERVER_CONNECTION_FILE);
		// // var serverConfigPath = Path.join(path, LOCAL_CONFIG_DIR, SERVER_CONNECTION_FILE);
		// var vagrant = config == 'vagrant';

		// //Get the configuration, either from the given file, or the locally installed.
		// return Promise.promise(true)
		// 	.pipe(function(_) {
		// 		//Some more complex checking here in case previous installs failed or containers have gone down.
		// 		if (FsExtends.existsSync(serverConnectionPath)) {
		// 			throw 'Found connection file at $serverConnectionJsonPath but no server configuration. Installing would overwrite the connection file'
		// 		}


		// 		if (vagrant) {
		// 			var serverConfig :ServiceConfiguration = InitConfigTools.parseConfig(Resource.getString('ServerConfigVagrant'));
		// 			return Promise.promise(serverConfig);
		// 		} else {
					
		// 		}
		// 	})
		// 	//We have a bare CoreOS instance now
		


		
		// var serverConfig :ServiceConfiguration = if (vagrant) {
		// 	trace('haxe.Resource.getString("ServerConfigVagrant")=${haxe.Resource.getString("ServerConfigVagrant")}');
		// 	InitConfigTools.parseConfig(haxe.Resource.getString('ServerConfigVagrant'));
		// } else if (config == null) {
		// 	InitConfigTools.getDefaultConfig();
		// } else {
		// 	InitConfigTools.getConfigFromFile(config);
		// }
		// trace('serverConfig=${serverConfig}');
		// return ProviderTools.buildRemoteServer(serverConfig.providers[0])
		// 	.then(function(serverBlob) {
		// 		trace('serverBlob=${serverBlob}');
		// 		// var serverblob :ServerConnectionBlob = {server:instanceDef};
		// 		// CliTools.writeServerConnection(serverblob);
		// 		return true;
		// 	});
		// return Promise.promise(true);
	}

	static function doJobCommand<T>(job :JobId, command :JobCLICommand) :Promise<T>
	{
		var host = getHost();
		var clientProxy = getProxy(host.rpcUrl());
		return clientProxy.doJobCommand(command, [job])
			.then(function(out) {
				var result :TypedDynamicObject<JobId, T> = cast out;
				var jobResult :T = result[job];
				return jobResult;
			});
	}

	static function getServerAddress() :Promise<Host>
	{
		return CliTools.getServerHost();
	}

	static function jsonString(blob :Dynamic) :String
	{
		return Json.stringify(blob, null, '\t');
	}

	static function getConfiguration() :ServiceConfiguration
	{
		return InitConfigTools.ohGodGetConfigFromSomewhere();
	}

	static function processInputItem(itemString :String) :ComputeInputSource
	{
		var tokens = itemString.split('=');
		var itemName = tokens.shift();
		var itemRef = tokens.join('=');
		if (itemRef.startsWith('@')) {
			var filePath = itemRef.substr(1);
			if (filePath.startsWith('http')) {
				return {
					type: InputSource.InputStream,
					value: Request.get(filePath, null),
					name: itemName,
					encoding: 'base64'
				}
			} else {
				return {
					type: InputSource.InputStream,
					value: Fs.createReadStream(filePath, {encoding:'base64'}),
					name: itemName,
					encoding: 'base64'
				}
			}
		} else {
			return {
				type: InputSource.InputInline,
				value: itemRef,
				name: itemName
			}
		}
	}

	inline static function log(message :Dynamic)
	{
#if nodejs
		js.Node.console.log(message);
#else
		trace(message);
#end
	}

	inline static function warn(message :Dynamic)
	{
#if nodejs
		js.Node.console.log(js.npm.CliColor.bold(js.npm.CliColor.red(message)));
#else
		trace(message);
#end
	}

	static var console = {
		log: function(s) {
			js.Node.process.stdout.write(s + '\n');
		},
		error: function(s) {
			js.Node.process.stderr.write(s + '\n');
		},
	}
}