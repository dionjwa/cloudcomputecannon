package ccc.compute.test.tests;

import ccc.compute.client.js.ClientJSTools;

import haxe.DynamicAccess;
import haxe.io.*;

import haxe.remoting.JsonRpc;

import js.node.Buffer;
import js.npm.shortid.ShortId;

import promhx.RequestPromises;
import promhx.deferred.DeferredPromise;

import util.DockerRegistryTools;
import util.streams.StreamTools;

class TestJobs extends ServerAPITestBase
{
	static var TEST_BASE = 'tests';

	@inject public var redis :RedisClient;

	@timeout(120000)
	public function testExitCodeZero() :Promise<Bool>
	{
		var routes = ProxyTools.getProxy(_serverHostRPCAPI);
		var script =
'#!/bin/sh
exit 0
';
		var scriptName = 'script.sh';
		var input :DataBlob = {
			source: DataSource.InputInline,
			value: script,
			name: scriptName
		}
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);

		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testExitCodeZero/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testExitCodeZero/$random/outputs';
		var customResultsPath = '$TEST_BASE/testExitCodeZero/$random/results';

		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [input], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.then(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				assertEquals(jobResult.exitCode, 0);
				return true;
			});
	}

	@timeout(120000)
	public function testExitCodeNonZeroScript() :Promise<Bool>
	{
		var routes = ProxyTools.getProxy(_serverHostRPCAPI);
		var exitCode = 3;
		var script =
'#!/bin/sh
exit $exitCode
';
		var scriptName = 'script.sh';
		var input :DataBlob = {
			source: DataSource.InputInline,
			value: script,
			name: scriptName
		}
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);

		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testExitCodeNonZeroScript/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testExitCodeNonZeroScript/$random/outputs';
		var customResultsPath = '$TEST_BASE/testExitCodeNonZeroScript/$random/results';

		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [input], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.then(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				assertEquals(jobResult.exitCode, exitCode);
				return true;
			});
	}

	@timeout(120000)
	public function testExitCodeNonZeroCommand() :Promise<Bool>
	{
		var routes = ProxyTools.getProxy(_serverHostRPCAPI);
		var exitCode = 4;
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);

		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testExitCodeNonZeroCommand/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testExitCodeNonZeroCommand/$random/outputs';
		var customResultsPath = '$TEST_BASE/testExitCodeNonZeroCommand/$random/results';

		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["/bin/sh", '-c', 'exit $exitCode'], [], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.then(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				assertEquals(jobResult.exitCode, exitCode);
				return true;
			});
	}

	@timeout(120000)
	public function testWaitForJob() :Promise<Bool>
	{
		var routes = ProxyTools.getProxy(_serverHostRPCAPI);
		var outputValueStdout = 'out${ShortId.generate()}';
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
		var waitForJobToFinish = true;
		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testWaitForJob/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testWaitForJob/$random/outputs';
		var customResultsPath = '$TEST_BASE/testWaitForJob/$random/results';
		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["/bin/sh", '-c', 'echo $outputValueStdout'], [], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath, waitForJobToFinish)
			.pipe(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				return Promise.promise(true)
					.pipe(function(_) {
						assertNotNull(jobResult.stdout);
						var stdoutUrl = jobResult.getStdoutUrl(_serverHostUrl);
						assertNotNull(stdoutUrl);
						return RequestPromises.get(stdoutUrl)
							.then(function(stdout) {
								stdout = stdout != null ? stdout.trim() : stdout;
								assertEquals(stdout, outputValueStdout);
								return true;
							});
					});
			});
	}

	@timeout(120000)
	public function testReadMultilineStdout() :Promise<Bool>
	{
		var routes = ProxyTools.getProxy(_serverHostRPCAPI);
		var outputValueStdout = 'out${ShortId.generate()}';
		var script =
'#!/bin/sh
echo "$outputValueStdout"
echo "$outputValueStdout"
echo foo
echo "$outputValueStdout"
';
		var compareOutput = '$outputValueStdout\n$outputValueStdout\nfoo\n$outputValueStdout'.trim();
		var scriptName = 'script.sh';
		var input :DataBlob = {
			source: DataSource.InputInline,
			value: script,
			name: scriptName
		}
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testReadMultilineStdout/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testReadMultilineStdout/$random/outputs';
		var customResultsPath = '$TEST_BASE/testReadMultilineStdout/$random/results';
		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [input], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}

				return Promise.promise(true)
					.pipe(function(_) {
						assertNotNull(jobResult.stdout);
						var stdoutUrl = jobResult.getStdoutUrl(_serverHostUrl);
						assertNotNull(stdoutUrl);
						return RequestPromises.get(stdoutUrl)
							.then(function(stdout) {
								stdout = stdout != null ? stdout.trim() : stdout;
								assertEquals(stdout, compareOutput);
								return true;
							});
					});
			});
	}

	@timeout(120000)
	public function testWriteStdoutAndStderr() :Promise<Bool>
	{
		var routes = ProxyTools.getProxy(_serverHostRPCAPI);
		var outputValueStdout = 'out${ShortId.generate()}';
		var outputValueStderr = 'out${ShortId.generate()}';
		var script =
'#!/bin/sh
echo "$outputValueStdout"
echo "$outputValueStderr" >>/dev/stderr
';
		var scriptName = 'script.sh';
		var input :DataBlob = {
			source: DataSource.InputInline,
			value: script,
			name: scriptName
		}
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testWriteStdoutAndStderr/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testWriteStdoutAndStderr/$random/outputs';
		var customResultsPath = '$TEST_BASE/testWriteStdoutAndStderr/$random/results';
		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [input], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}

				return Promise.promise(true)
					.pipe(function(_) {
						assertNotNull(jobResult.stderr);
						var stderrUrl = jobResult.getStderrUrl(_serverHostUrl);
						assertNotNull(stderrUrl);
						return RequestPromises.get(stderrUrl)
							.then(function(stderr) {
								stderr = stderr != null ? stderr.trim() : stderr;
								assertEquals(stderr, outputValueStderr);
								return true;
							});
					})
					.pipe(function(_) {
						assertNotNull(jobResult.stdout);
						var stdoutUrl = jobResult.getStdoutUrl(_serverHostUrl);
						assertNotNull(stdoutUrl);
						return RequestPromises.get(stdoutUrl)
							.then(function(stdout) {
								stdout = stdout != null ? stdout.trim() : stdout;
								assertEquals(stdout, outputValueStdout);
								return true;
							});
					});
			});
	}

	@timeout(120000)
	public function testReadInput() :Promise<Bool>
	{
		var routes = ProxyTools.getProxy(_serverHostRPCAPI);
		var inputValue = 'in${Std.int(Math.random() * 100000000)}';
		var inputName = 'in${Std.int(Math.random() * 100000000)}';
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
		var input :DataBlob = {
			source: DataSource.InputInline,
			value: inputValue,
			name: inputName
		}
		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testReadInput/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testReadInput/$random/outputs';
		var customResultsPath = '$TEST_BASE/testReadInput/$random/results';
		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["cat", '/$DIRECTORY_INPUTS/$inputName'], [input], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				var stdOutUrl = jobResult.getStdoutUrl(_serverHostUrl);
				assertNotNull(stdOutUrl);
				return RequestPromises.get(stdOutUrl)
					.then(function(stdout) {
						assertNotNull(stdout);
						stdout = stdout.trim();
						assertEquals(stdout.length, inputValue.length);
						assertEquals(stdout, inputValue);
						return true;
					});
			});
	}

	@timeout(120000)
	public function testWriteOutput() :Promise<Bool>
	{
		var routes = ProxyTools.getProxy(_serverHostRPCAPI);
		var outputValue = 'out${Std.int(Math.random() * 100000000)}';
		var outputName = 'out${Std.int(Math.random() * 100000000)}';
		var script =
'#!/bin/sh
echo "$outputValue" > /$DIRECTORY_OUTPUTS/$outputName
';
		var scriptName = 'script.sh';
		var input :DataBlob = {
			source: DataSource.InputInline,
			value: script,
			name: scriptName
		}
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testWriteOutput/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testWriteOutput/$random/outputs';
		var customResultsPath = '$TEST_BASE/testWriteOutput/$random/results';
		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [input], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				var outputs = jobResult.outputs != null ? jobResult.outputs : [];
				assertTrue(outputs.length == 1);
				var outputUrl = jobResult.getOutputUrl(outputs[0], _serverHostUrl);
				return RequestPromises.get(outputUrl)
					.then(function(out) {
						out = out != null ? out.trim() : out;
						assertEquals(out, outputValue);
						return true;
					});
			});
	}

	@timeout(120000)
	public function testBinaryInputAndOutput() :Promise<Bool>
	{
		// Create bytes for inputs. We'll test the output bytes
		// against these
		var routes = ProxyTools.getProxy(_serverHostRPCAPI);
		var bytes1 = new Buffer([Std.int(Math.random() * 1000), Std.int(Math.random() * 1000), Std.int(Math.random() * 1000)]);
		var inputName1 = 'in${Std.int(Math.random() * 100000000)}';
		var outputName1 = 'out${Std.int(Math.random() * 100000000)}';

		var inputBinaryValue1 :DataBlob = {
			source: DataSource.InputInline,
			value: bytes1.toString('base64'),
			name: inputName1,
			encoding: DataEncoding.base64
		}

		var bytes2 = new Buffer('somestring${Std.int(Math.random() * 100000000)}', 'utf8');
		var inputName2 = 'in${Std.int(Math.random() * 100000000)}';
		var outputName2 = 'out${Std.int(Math.random() * 100000000)}';

		var inputBinaryValue2 :DataBlob = {
			source: DataSource.InputInline,
			value: bytes2.toString('base64'),
			name: inputName2,
			encoding: DataEncoding.base64
		}

		//A script that copies the inputs to outputs
		var script =
'#!/bin/sh
cp /$DIRECTORY_INPUTS/$inputName1 /$DIRECTORY_OUTPUTS/$outputName1
cp /$DIRECTORY_INPUTS/$inputName2 /$DIRECTORY_OUTPUTS/$outputName2
';
		var scriptName = 'script.sh';
		var inputScript :DataBlob = {
			source: DataSource.InputInline,
			value: script,
			name: scriptName,
			encoding: DataEncoding.utf8 //Default
		}
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/outputs';
		var customResultsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/results';
		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [inputScript, inputBinaryValue1, inputBinaryValue2], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				var outputs = jobResult.outputs != null ? jobResult.outputs : [];
				assertTrue(outputs.length == 2);
				var outputUrl1 = jobResult.getOutputUrl(outputName1, _serverHostUrl);
				return RequestPromises.getBuffer(outputUrl1)
					.pipe(function(out1) {
						assertNotNull(out1);
						assertEquals(out1.compare(bytes1), 0);
						var outputUrl2 = jobResult.getOutputUrl(outputName2, _serverHostUrl);
						return RequestPromises.getBuffer(outputUrl2)
							.then(function(out2) {
								assertNotNull(out2);
								assertEquals(out2.compare(bytes2), 0);
								return true;
							});
					});
			});
	}

	@timeout(120000)
	public function testMultipartRPCSubmission() :Promise<Bool>
	{
		var routes = ProxyTools.getProxy(_serverHostRPCAPI);
		var url = 'http://${_serverHost}${SERVER_RPC_URL}';

		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/outputs';
		var customResultsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/results';

		// Create bytes for inputs. We'll test the output bytes
		// against these
		var bytes1 = new Buffer([Std.int(Math.random() * 1000), Std.int(Math.random() * 1000), Std.int(Math.random() * 1000)]);
		var inputName1 = 'in${Std.int(Math.random() * 100000000)}';
		var outputName1 = 'out${Std.int(Math.random() * 100000000)}';

		var bytes2 = new Buffer('somestring${Std.int(Math.random() * 100000000)}', 'utf8');
		var inputName2 = 'in${Std.int(Math.random() * 100000000)}';
		var outputName2 = 'out${Std.int(Math.random() * 100000000)}';

		//A script that copies the inputs to outputs
		var script =
'#!/bin/sh
cp /$DIRECTORY_INPUTS/$inputName1 /$DIRECTORY_OUTPUTS/$outputName1
cp /$DIRECTORY_INPUTS/$inputName2 /$DIRECTORY_OUTPUTS/$outputName2
';
		var scriptName = 'script.sh';

		var jobSubmissionOptions :BasicBatchProcessRequest = {
			image: DOCKER_IMAGE_DEFAULT,
			cmd: ['/bin/sh', '/$DIRECTORY_INPUTS/$scriptName'],
			inputs: [], //inputs are part of the multipart message (formStreams)
			parameters: {cpus:1, maxDuration:20*60*100000},
			//Custom paths
			outputsPath: customOutputsPath,
			inputsPath: customInputsPath,
			resultsPath: customResultsPath,
			wait: true
		};

		var formData :DynamicAccess<Dynamic> = {};
		formData[JsonRpcConstants.MULTIPART_JSONRPC_KEY] = Json.stringify(
			{
				method: RPC_METHOD_JOB_SUBMIT,
				params: jobSubmissionOptions,
				jsonrpc: JsonRpcConstants.JSONRPC_VERSION_2

			});
		formData[scriptName] = script;
		formData[inputName1] = bytes1;
		formData[inputName2] = bytes2;

		var promise = new DeferredPromise();
		js.npm.request.Request.post({url:url, formData: formData},
			function(err, httpResponse, body) {
				if (err != null) {
					promise.boundPromise.reject(err);
					return;
				}
				if (httpResponse.statusCode == 200) {
					try {
						Promise.promise(true)
							.pipe(function(out) {
								var jobIdResult :{result:{jobId:String}} = Json.parse(body);
								return ServerTestTools.getJobResult(jobIdResult.result.jobId);
							})
							.pipe(function(jobResult :JobResultAbstract) {
								if (jobResult == null) {
									throw 'jobResult should not be null. Check the above section';
								}
								var outputs = jobResult.outputs != null ? jobResult.outputs : [];
								assertEquals(outputs.length, 2);
								var outputUrl1 = jobResult.getOutputUrl(outputName1, _serverHostUrl);
								return RequestPromises.getBuffer(outputUrl1)
									.pipe(function(out1) {
										assertNotNull(out1);
										assertEquals(out1.compare(bytes1), 0);
										var outputUrl2 = jobResult.getOutputUrl(outputName2, _serverHostUrl);
										return RequestPromises.getBuffer(outputUrl2)
											.then(function(out2) {
												assertNotNull(out2);
												assertEquals(out2.compare(bytes2), 0);
												return true;
											});
									});
							})
							.then(function(passed) {
								promise.resolve(passed);
							});
					} catch (err :Dynamic) {
						promise.boundPromise.reject(err);
					}
				} else {
					promise.boundPromise.reject('non-200 response body=' + body);
				}
			});

		return promise.boundPromise;
	}

	@timeout(120000)
	public function testMultipartRPCSubmissionJsonRpcNotFirst404() :Promise<Bool>
	{
		var routes = ProxyTools.getProxy(_serverHostRPCAPI);
		var url = 'http://${_serverHost}${SERVER_RPC_URL}';

		var random = ShortId.generate();

		// Create bytes for inputs. We'll test the output bytes
		// against these
		var bytes1 = new Buffer([Std.int(Math.random() * 1000), Std.int(Math.random() * 1000), Std.int(Math.random() * 1000)]).toString('utf8');
		var inputName1 = 'in${Std.int(Math.random() * 100000000)}';
		var outputName1 = 'out${Std.int(Math.random() * 100000000)}';

		var bytes2 = new Buffer('somestring${Std.int(Math.random() * 100000000)}', 'utf8').toString('utf8');
		var inputName2 = 'in${Std.int(Math.random() * 100000000)}';
		var outputName2 = 'out${Std.int(Math.random() * 100000000)}';

		var jobSubmissionOptions :BasicBatchProcessRequest = {
			id: 'testMultipartRPCSubmissionJsonRpcNotFirst404.$random',
			image: DOCKER_IMAGE_DEFAULT,
			cmd: ['/bin/sh', 'echo foo'],
			wait: true
		};

		var formData :DynamicAccess<Dynamic> = {};
		//Notice I'm putting the JSON bit inbetween the other inputs
		//BUT this is a map, not an array. Strictly speaking, this should
		//sporadically fail, however, most implementations of Javascript
		//keep insertion order, so we'll exploit that here because there's
		//no explicit array-like object for the multipart form data elements
		//https://stackoverflow.com/questions/9179680/is-it-acceptable-style-for-node-js-libraries-to-rely-on-object-key-order
		formData[inputName1] = bytes1;
		formData[JsonRpcConstants.MULTIPART_JSONRPC_KEY] = Json.stringify(
			{
				method: RPC_METHOD_JOB_SUBMIT,
				params: jobSubmissionOptions,
				jsonrpc: JsonRpcConstants.JSONRPC_VERSION_2

			});
		formData[inputName2] = bytes2;

		var promise = new DeferredPromise();
		js.npm.request.Request.post({url:url, formData: formData},
			function(err, httpResponse, body) {
				if (err != null) {
					traceYellow(err);
					promise.boundPromise.reject(err);
					return;
				}
				assertEquals(httpResponse.statusCode, 404);
				promise.resolve(true);
			});

		return promise.boundPromise;
	}

	@timeout(120000)
	public function testMultipartRPCSubmissionAndWait() :Promise<Bool>
	{
		var routes = ProxyTools.getProxy(_serverHostRPCAPI);
		var url = 'http://${_serverHost}${SERVER_RPC_URL}';

		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/outputs';
		var customResultsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/results';

		// Create bytes for inputs. We'll test the output bytes
		// against these
		var bytes1 = new Buffer([Std.int(Math.random() * 1000), Std.int(Math.random() * 1000), Std.int(Math.random() * 1000)]);
		var inputName1 = 'in${Std.int(Math.random() * 100000000)}';
		var outputName1 = 'out${Std.int(Math.random() * 100000000)}';

		var bytes2 = new Buffer('somestring${Std.int(Math.random() * 100000000)}', 'utf8');
		var inputName2 = 'in${Std.int(Math.random() * 100000000)}';
		var outputName2 = 'out${Std.int(Math.random() * 100000000)}';

		//A script that copies the inputs to outputs
		var script =
'#!/bin/sh
cp /$DIRECTORY_INPUTS/$inputName1 /$DIRECTORY_OUTPUTS/$outputName1
cp /$DIRECTORY_INPUTS/$inputName2 /$DIRECTORY_OUTPUTS/$outputName2
';
		var scriptName = 'script.sh';

		var jobSubmissionOptions :BasicBatchProcessRequest = {
			image: DOCKER_IMAGE_DEFAULT,
			cmd: ['/bin/sh', '/$DIRECTORY_INPUTS/$scriptName'],
			inputs: [], //inputs are part of the multipart message (formStreams)
			parameters: {cpus:1, maxDuration:20*60*100000},
			//Custom paths
			outputsPath: customOutputsPath,
			inputsPath: customInputsPath,
			resultsPath: customResultsPath,
			wait: true
		};

		var formData :DynamicAccess<Dynamic> = {};
		formData[JsonRpcConstants.MULTIPART_JSONRPC_KEY] = Json.stringify(
			{
				method: RPC_METHOD_JOB_SUBMIT,
				params: jobSubmissionOptions,
				jsonrpc: JsonRpcConstants.JSONRPC_VERSION_2

			});
		formData[scriptName] = script;
		formData[inputName1] = bytes1;
		formData[inputName2] = bytes2;

		var promise = new DeferredPromise();
		js.npm.request.Request.post({url:url, formData: formData},
			function(err, httpResponse, body) {
				if (err != null) {
					promise.boundPromise.reject(err);
					return;
				}
				if (httpResponse.statusCode == 200) {
					try {
						Promise.promise(true)
							.then(function(out) {
								var rpcResult :{result:JobResult} = Json.parse(body);
								return rpcResult.result;
							})
							.pipe(function(jobResult :JobResultAbstract) {
								if (jobResult == null) {
									throw 'jobResult should not be null. Check the above section';
								}
								var outputs = jobResult.outputs != null ? jobResult.outputs : [];
								assertEquals(outputs.length, 2);
								var outputUrl1 = jobResult.getOutputUrl(outputName1, _serverHostUrl);
								return RequestPromises.getBuffer(outputUrl1)
									.pipe(function(out1) {
										assertNotNull(out1);
										assertEquals(out1.compare(bytes1), 0);
										var outputUrl2 = jobResult.getOutputUrl(outputName2, _serverHostUrl);
										return RequestPromises.getBuffer(outputUrl2)
											.then(function(out2) {
												assertNotNull(out2);
												assertEquals(out2.compare(bytes2), 0);
												return true;
											});
									});
							})
							.then(function(passed) {
								promise.resolve(passed);
							});
					} catch (err :Dynamic) {
						promise.boundPromise.reject(err);
					}
				} else {
					promise.boundPromise.reject('non-200 response body=' + body);
				}
			});

		return promise.boundPromise;
	}

	@timeout(120000)
	public function testMultipartRPCSubmissionAndWaitNonZeroExitCode() :Promise<Bool>
	{
		var routes = ProxyTools.getProxy(_serverHostRPCAPI);
		var url = 'http://${_serverHost}${SERVER_RPC_URL}';
		var exitCode = 3;
		var script =
'#!/bin/sh
exit $exitCode
';
		var scriptName = 'script.sh';

		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testMultipartRPCSubmissionAndWaitNonZeroExitCode/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testMultipartRPCSubmissionAndWaitNonZeroExitCode/$random/outputs';
		var customResultsPath = '$TEST_BASE/testMultipartRPCSubmissionAndWaitNonZeroExitCode/$random/results';

		var jobSubmissionOptions :BasicBatchProcessRequest = {
			image: DOCKER_IMAGE_DEFAULT,
			cmd: ['/bin/sh', '/$DIRECTORY_INPUTS/$scriptName'],
			inputs: [],
			parameters: {cpus:1, maxDuration:20*60*100000},
			outputsPath: customOutputsPath,
			inputsPath: customInputsPath,
			resultsPath: customResultsPath,
			wait: true,
			appendStdOut: true,
			appendStdErr: true
		};

		var formData :DynamicAccess<Dynamic> = {};
		formData[JsonRpcConstants.MULTIPART_JSONRPC_KEY] = Json.stringify(
			{
				method: RPC_METHOD_JOB_SUBMIT,
				params: jobSubmissionOptions,
				jsonrpc: JsonRpcConstants.JSONRPC_VERSION_2

			});
		formData[scriptName] = script;

		var promise = new DeferredPromise();
		js.npm.request.Request.post({url:url, formData: formData},
			function(err, httpResponse, body) {
				if (err != null) {
					promise.boundPromise.reject(err);
					return;
				}
				if (httpResponse.statusCode == 200) {
					try {
						Promise.promise(true)
							.then(function(out) {
								var rpcResult :{result:JobResult} = Json.parse(body);
								return rpcResult.result;
							})
							.then(function(jobResult :JobResultAbstract) {
								if (jobResult == null) {
									throw 'jobResult should not be null. Check the above section';
								}
								return true;
							})
							.then(function(passed) {
								promise.resolve(passed);
							});
					} catch (err :Dynamic) {
						promise.boundPromise.reject(err);
					}
				} else {
					promise.boundPromise.reject('non-200 response body=' + body);
				}
			});

		return promise.boundPromise;
	}

	@timeout(120000)
	public function testMultipartRPCSubmissionBadDockerImage() :Promise<Bool>
	{
		var routes = ProxyTools.getProxy(_serverHostRPCAPI);
		var url = 'http://${_serverHost}${SERVER_RPC_URL}';
		var script =
'#!/bin/sh
exit 0
';
		var scriptName = 'script.sh';

		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testMultipartRPCSubmissionBadDockerImage/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testMultipartRPCSubmissionBadDockerImage/$random/outputs';
		var customResultsPath = '$TEST_BASE/testMultipartRPCSubmissionBadDockerImage/$random/results';

		var jobSubmissionOptions :BasicBatchProcessRequest = {
			image: 'this_docker_image_is_fubar',
			cmd: ['/bin/sh', '/$DIRECTORY_INPUTS/$scriptName'],
			inputs: [],
			parameters: {cpus:1, maxDuration:20*60*100000},
			outputsPath: customOutputsPath,
			inputsPath: customInputsPath,
			resultsPath: customResultsPath,
			wait: true
		};

		var formData :DynamicAccess<Dynamic> = {};
		formData[JsonRpcConstants.MULTIPART_JSONRPC_KEY] = Json.stringify(
			{
				method: RPC_METHOD_JOB_SUBMIT,
				params: jobSubmissionOptions,
				jsonrpc: JsonRpcConstants.JSONRPC_VERSION_2

			});
		formData[scriptName] = script;

		var promise = new DeferredPromise();
		js.npm.request.Request.post({url:url, formData: formData},
			function(err, httpResponse, body) {
				if (err != null) {
					promise.boundPromise.reject(err);
					return;
				}
				promise.resolve(httpResponse.statusCode == 400);
			});

		return promise.boundPromise;
	}

	/**
	 * See docs for testRegularRPCSubmissionCustomId below.
	 */
	@timeout(120000)
	public function testMultipartRPCSubmissionCustomId() :Promise<Bool>
	{
		var id = 'testMultipartRPCSubmissionCustomId${ShortId.generate()}';

		var jobSubmissionOptions :BasicBatchProcessRequest = {
			id: id, //This will be the same below
			image: DOCKER_IMAGE_DEFAULT,
			cmd: ['echo', 'testMultipartRPCSubmissionCustomId'],
			inputs: [],
			wait: true
		};

		var formData :DynamicAccess<Dynamic> = {};
		formData[JsonRpcConstants.MULTIPART_JSONRPC_KEY] = Json.stringify(
			{
				method: RPC_METHOD_JOB_SUBMIT,
				params: jobSubmissionOptions,
				jsonrpc: JsonRpcConstants.JSONRPC_VERSION_2

			});
		formData["arbitrary"] = "unfortunately i am also arbitrary, and not even a key";

		var promise = new DeferredPromise();
		var url = 'http://${_serverHost}${SERVER_RPC_URL}';
		js.npm.request.Request.post({url:url, formData: formData},
			function(err, httpResponse, body) {
				if (err != null) {
					promise.boundPromise.reject(err);
					return;
				}
				var jsonRpcResponse :ResponseDef = Json.parse(body);
				var jobResult :JobResult = jsonRpcResponse.result;
				assertEquals(jobResult.jobId, id);
				promise.resolve(true);
			});

		return promise.boundPromise;
	}

	/**
	 * This is needed in addition to testMultipartRPCSubmissionCustomId
	 * because they are two different code paths where this logic is
	 * concerned. It would be nice to not have the duplication, but multipart
	 * requests have many more edge cases, so you need time to think
	 * through them all.
	 */
	@timeout(120000)
	public function testRegularRPCSubmissionCustomId() :Promise<Bool>
	{
		var id = 'testRegularRPCSubmissionCustomId${ShortId.generate()}';

		var jobRequest :BasicBatchProcessRequest = {
			id: id, //This will be the same below
			image: DOCKER_IMAGE_DEFAULT,
			cmd: ['echo', 'foo'],
			inputs: [],
			wait: true
		};

		var routes = ProxyTools.getProxy(_serverHostRPCAPI);

		return routes.submitJobJson(jobRequest)
			.then(function(jobResult) {
				assertEquals(jobResult.jobId, id);
			})
			.thenTrue();
	}

	/**
	 * Checks that the global record of the last job time
	 * matches the known last job time. This value is used
	 * by the scaling lambdas, so that can only scale down
	 * workers if there have been no jobs in the last given
	 * time interval.
	 */
	@timeout(60000)
	public function testLastJobTimes() :Promise<Bool>
	{
		function getLastJobTime(bullQueue :BullQueueNames) :Promise<Float> {
			return RedisPromises.hget(redis, REDIS_HASH_TIME_LAST_JOB_FINISHED, bullQueue)
				.then(function(time) {
					if (time != null && time != "") {
						return Std.parseFloat(time);
					} else {
						return -1;
					}
				});
		}
		var promises = [];
		[true, false].iter(function(isGpu) {
			var jobStuff = ServerTestTools.createTestJobAndExpectedResults('testLastJobTimes', 1, false, isGpu);
			jobStuff.request.wait = true;

			var p = ClientJSTools.postJob(_serverHost, jobStuff.request)
				.pipe(function(jobResult) {
					assertNotNull(jobResult);
					assertNotNull(jobResult.jobId);
					return getLastJobTime(isGpu ? BullQueueNames.JobQueueGpu : BullQueueNames.JobQueue)
						.pipe(function(lastJobTime) {
							return JobStatsTools.getJobStatsData(jobResult.jobId)
								.then(function(jobStats) {
									assertEquals(jobStats.finished, lastJobTime);
									return true;
								});
						});
				});
			promises.push(p);
		});
		return Promise.whenAll(promises).thenTrue();
	}

	@timeout(5000)
	public function testCorrect404HttpStatusCodeForMissingJobInJobCommands() :Promise<Bool>
	{
		var apisFor404 = ['status', 'result', 'stats', 'definition', 'time'];

		var promises = apisFor404.map(function(api) {
			var url = '${_serverHostRPCAPI}/job/$api/fakejob';
			var promise = new DeferredPromise();
			js.npm.request.Request.get(url,
				function(err, httpResponse, body) {
					traceYellow('api=$api = ${httpResponse.statusCode} body=$body');
					assertEquals(httpResponse.statusCode, 404);
					if (err != null) {
						promise.boundPromise.reject(err);
						return;
					}
					promise.resolve(httpResponse.statusCode == 404);
				});

			return promise.boundPromise;
		});

		return Promise.whenAll(promises)
			.thenTrue();
	}

	@timeout(5000)
	public function testCorrect200HttpStatusCodeForMissingJobInSomeJobCommands() :Promise<Bool>
	{
		var apisFor404 = ['remove', 'kill'];

		var promises = apisFor404.map(function(api) {
			var url = '${_serverHostRPCAPI}/job/$api/fakejob';
			var promise = new DeferredPromise();
			js.npm.request.Request.get(url,
				function(err, httpResponse, body) {
					assertEquals(httpResponse.statusCode, 200);
					if (err != null) {
						promise.boundPromise.reject(err);
						return;
					}
					promise.resolve(httpResponse.statusCode == 200);
				});

			return promise.boundPromise;
		});

		return Promise.whenAll(promises)
			.thenTrue();
	}

	public function new() { super(); }
}