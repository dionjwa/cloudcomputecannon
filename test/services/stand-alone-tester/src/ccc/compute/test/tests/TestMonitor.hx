package ccc.compute.test.tests;

import ccc.compute.server.services.ServiceMonitorRequest;

using promhx.PromiseTools;

class TestMonitor
	extends haxe.unit.async.PromiseTest
{
	@timeout(2000)
	public function testDCCServerReachable() :Promise<Bool>
	{
		var url = 'http://${ServerTesterConfig.DCC}/version';
		return RequestPromises.get(url)
			.then(function(result) {
				return true;
			});
	}

	@timeout(24000)
	public function testMonitorReturnSignature() :Promise<Bool>
	{
		return Promise.promise(true)
			.pipe(function(_) {
				return RetryPromise.retryRegular(getMonitorResult.bind(10000), 5, 1000, 'getMonitorResult');
			})
			.then(function(result) {
				assertTrue(Reflect.hasField(result, 'success'));
				assertEquals(result.success, true);
				return true;
			});
	}

	@timeout(24000)
	public function testMultipleMonitorEvents() :Promise<Bool>
	{
		//Kill all jobs
		var promises = [];

		function callMonitor(delay) {
			var p = PromiseTools.delay(delay)
				.pipe(function(_) {
					return RetryPromise.retryRegular(getMonitorResult.bind(10000), 5, 1000, 'getMonitorResult');
				})
				.then(function(result) {
					assertEquals(result.success, true);
					return true;
				});
			promises.push(p);
		}

		function checkOnlyOneTestJob(delay :Int) {
			var p = PromiseTools.delay(delay)
				.pipe(function(_) {
					return RetryPromise.retryRegular(getMonitorJobCount, 5, 1000, 'getMonitorJobCount');
				})
				.then(function(count) {
					assertTrue(count <= 1);
					return true;
				});
			promises.push(p);
		}

		promises.push(JobStateTools.cancelAllJobs().thenWait(300));

		callMonitor(0);
		checkOnlyOneTestJob(0);
		for (i in 3...6) {
			callMonitor(100 * i);
		}

		for (i in 1...6) {
			callMonitor(500 * i);
		}
		checkOnlyOneTestJob(1000);
		checkOnlyOneTestJob(5000);

		for (i in 1...6) {
			callMonitor(1000 * i);
		}

		checkOnlyOneTestJob(10000);

		return Promise.whenAll(promises)
			.thenTrue();
	}

	@timeout(10000)
	public function testMonitorShortTimeout() :Promise<Bool>
	{
		var timeout = 5;
		var returned = false;
		var promise = new DeferredPromise();
		var timeoutId = Node.setTimeout(function() {
			if (!returned) {
				returned = true;
				promise.boundPromise.reject('testMonitorShortTimeout timed out');
			} else {
				promise.resolve(true);
			}
		}, Std.int((timeout + 1) * 1000));

		getMonitorResult(60, 5)
			.then(function(result) {
				if (!returned) {
					returned = true;
					promise.resolve(true);
					Node.clearTimeout(timeoutId);
				}
			})
			.catchError(function(err) {
				if (!returned) {
					returned = true;
					promise.boundPromise.reject(err);
					Node.clearTimeout(timeoutId);
				}
			});

		return promise.boundPromise;
	}

	public static function getMonitorResult(?within :Null<Int>, ?timeout :Null<Int>) :Promise<ServiceMonitorRequestResult>
	{
		var url = 'http://${ServerTesterConfig.DCC}${ServiceMonitorRequest.ROUTE_MONITOR}';
		if (within != null) {
			url = '$url?within=$within';
		}
		if (timeout != null) {
			if (url.indexOf('?') > 1) {
				url = '$url&timeout=$timeout';
			} else {
				url = '$url?timeout=$timeout';
			}
		}
		return RequestPromises.get(url)
			.then(Json.parse);
	}

	public static function getMonitorJobCount() :Promise<Int>
	{
		var url = 'http://${ServerTesterConfig.DCC}${ServiceMonitorRequest.ROUTE_MONITOR_JOB_COUNT}';
		return RequestPromises.get(url)
			.then(Json.parse)
			.then(function(json :{count :Int}) {
				return json.count;
			});
	}
}