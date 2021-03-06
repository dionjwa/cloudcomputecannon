package ccc;

/**
 * Example:
 * {
	jobId : asd74gf,
	status : Success,
	exitCode : 0,
	stdout : https://sr-url/3519F65B-10EA-46F3-92F8-368CF377DFCF/stdout,
	stderr : https://sr-url/3519F65B-10EA-46F3-92F8-368CF377DFCF/stderr,
	resultJson : https://sr-url/3519F65B-10EA-46F3-92F8-368CF377DFCF/result.json,
	inputsBaseUrl : https://sr-url/3519F65B-10EA-46F3-92F8-368CF377DFCF/inputs/,
	outputsBaseUrl : https://sr-url/3519F65B-10EA-46F3-92F8-368CF377DFCF/outputs/,
	inputs : [script.sh],
	outputs : [bar]
}
 */
typedef JobResult = {
	var jobId :JobId;
	@:optional var status :JobFinishedStatus;
	@:optional var exitCode :Int;
	@:optional var stdout :String;
	@:optional var stderr :String;
	@:optional var resultJson :String;
	@:optional var inputsBaseUrl :String;
	@:optional var inputs :Array<String>;
	@:optional var outputsBaseUrl :String;
	@:optional var outputs :Array<String>;
	@:optional var error :Dynamic;
	@:optional var stats :PrettyStatsData;
	@:optional var definition :DockerBatchComputeJob;
}