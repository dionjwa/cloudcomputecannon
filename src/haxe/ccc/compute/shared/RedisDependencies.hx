package ccc.compute.shared;

import js.npm.redis.RedisClient;
import js.npm.Redis;

import minject.Injector;

import promhx.Promise;

import t9.redis.ServerRedisClient;

class RedisDependencies
{
	/**
	 * injector.map(Int, 'REDIS_PORT').toValue(9999)
	 * injector.map(String, 'REDIS_HOST').toValue('some.host')
	 */
	inline public static var REDIS_PORT = 'REDIS_PORT';
	inline public static var REDIS_HOST = 'REDIS_HOST';

	public static function mapRedisAndInitializeAll(injector :Injector, redisHost :String, ?redisPort :Int = 6379) :Promise<Bool>
	{
		mapRedis(injector, redisHost, redisPort);
		return initRedis(injector)
			.pipe(function(_) {
				return initDependencies(injector);
			});
	}

	public static function mapRedis(injector :Injector, redisHost :String, ?redisPort :Int = 6379)
	{
		injector.map(Int, REDIS_PORT).toValue(redisPort);
		injector.map(String, REDIS_HOST).toValue(redisHost);
	}

	public static function initRedis(injector :Injector) :Promise<Bool>
	{
		var opts = {
			port: injector.getValue(Int, REDIS_PORT),
			host: injector.getValue(String, REDIS_HOST)
		}
		return ServerRedisClient.createClient(opts)
			.then(function(redisClients) {
				injector.map(ServerRedisClient).toValue(redisClients);
				injector.map(RedisClient).toValue(redisClients.client);
				return true;
			});
	}

	/**
	 * Assumes RedisClient is already set
	 * @param  injector :Injector     [description]
	 * @return          [description]
	 */
	public static function initDependencies(injector :Injector) :Promise<Bool>
	{
		var redis = injector.getValue(RedisClient);
		//No dependencies between these, so init concurrently
		return Promise.whenAll([
			ccc.compute.worker.job.stats.JobStatsTools.init(redis),
			ccc.compute.worker.job.state.JobStateTools.init(redis),
			ccc.compute.worker.job.Jobs.init(redis),
			ccc.compute.worker.job.JobStream.init(redis),
			ccc.lambda.RedisLogGetter.init(redis),
			ccc.WorkerStateRedis.init(redis),
			ccc.compute.server.services.status.SystemStatusManager.init(redis),
			ccc.compute.server.services.queue.BullQueueJobTools.init(redis),

		]).thenTrue();
	}
}