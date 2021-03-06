package ccc.compute.client.util;

import t9.abstracts.net.UrlString;
import t9.remoting.jsonrpc.JsonRpcConnectionHttpPost;

/**
 * CLI tools for client/server/proxies.
 */
class ProxyTools
{
	public static function getProxy(rpcUrl :UrlString, ?headers :Dynamic)
	{
		var proxy = t9.remoting.jsonrpc.Macros.buildRpcClient(ccc.compute.server.execution.routes.RpcRoutes)
			.setConnection(new JsonRpcConnectionHttpPost(rpcUrl).addHeaders(headers));
		return proxy;
	}
}