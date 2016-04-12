module.exports =
	typeof window === 'object' && window != null && window === window.window
	? require('./browser')
	: require('./node');
