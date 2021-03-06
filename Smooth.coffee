###
Smooth.js version 0.1.5

Turn arrays into smooth functions.

Copyright 2012 Spencer Cohen
Licensed under MIT license (see "Smooth.js MIT license.txt")

###


###Constants (these are accessible by Smooth.WHATEVER in user space)###
Enum = 
	###Interpolation methods###
	METHOD_NEAREST: 'nearest' #Rounds to nearest whole index
	METHOD_LINEAR: 'linear' 
	METHOD_CUBIC: 'cubic' # Default: cubic interpolation
	METHOD_LANCZOS: 'lanczos'
	METHOD_SINC: 'sinc'

	###Input clipping modes###
	CLIP_CLAMP: 'clamp' # Default: clamp to [0, arr.length-1]
	CLIP_ZERO: 'zero' # When out of bounds, clip to zero
	CLIP_PERIODIC: 'periodic' # Repeat the array infinitely in either direction
	CLIP_MIRROR: 'mirror' # Repeat infinitely in either direction, flipping each time

	### Constants for control over the cubic interpolation tension ###
	CUBIC_TENSION_DEFAULT: 0 # Default tension value
	CUBIC_TENSION_CATMULL_ROM: 0


defaultConfig = 
	method: Enum.METHOD_CUBIC                       #The interpolation method
	
	cubicTension: Enum.CUBIC_TENSION_DEFAULT        #The cubic tension parameter
	
	clip: Enum.CLIP_CLAMP                           #The clipping mode
	
	scaleTo: 0                                      #The scale-to value (0 means don't scale) (can also be a range)
	
	sincFilterSize: 2                               #The size of the sinc filter kernel (must be an integer)

	sincWindow: undefined                           #The window function for the sinc filter

###Index clipping functions###
clipClamp = (i, n) -> Math.max 0, Math.min i, n - 1

clipPeriodic = (i, n) ->
	i = i % n #wrap
	i += n if i < 0 #if negative, wrap back around
	i

clipMirror = (i, n) ->
	period = 2*(n - 1) #period of index mirroring function
	i = clipPeriodic i, period
	i = period - i if i > n - 1 #flip when out of bounds 
	i


###
Abstract scalar interpolation class which provides common functionality for all interpolators

Subclasses must override interpolate().
###

class AbstractInterpolator

	constructor: (array, config) ->
		@array = array.slice 0 #copy the array
		@length = @array.length #cache length


		clipHelpers = 
			clamp: @clipHelperClamp
			zero: @clipHelperZero
			periodic: @clipHelperPeriodic
			mirror: @clipHelperMirror

		#Set the clipping helper method
		@clipHelper = clipHelpers[config.clip]

		throw "Invalid clip: #{config.clip}" unless @clipHelper?
				

    # Get input array value at i, applying the clipping method
	getClippedInput: (i) ->
		#Normal behavior for indexes within bounds
		if 0 <= i < @length
			@array[i]
		else
			@clipHelper i

	clipHelperClamp: (i) -> @array[clipClamp i, @length]

	clipHelperZero: (i) -> 0

	clipHelperPeriodic: (i) -> @array[clipPeriodic i, @length]

	clipHelperMirror: (i) -> @array[clipMirror i, @length]

	interpolate: (t) -> throw 'Subclasses of AbstractInterpolator must override the interpolate() method.'


#Nearest neighbor interpolator (round to whole index)
class NearestInterpolator extends AbstractInterpolator
	interpolate: (t) -> @getClippedInput Math.round t


#Linear interpolator (first order Bezier)
class LinearInterpolator extends AbstractInterpolator
	interpolate: (t) ->
		k = Math.floor t
		a = @getClippedInput k
		b = @getClippedInput k+1
		#Translate t to interpolate between k and k+1
		t -= k
		return (1-t)*a + (t)*b


class CubicInterpolator extends AbstractInterpolator
	constructor: (array, config)->
		@tangentFactor = 1 - Math.max 0, Math.min 1, config.cubicTension
		super

	# Cardinal spline with tension 0.5)
	getTangent: (k) -> @tangentFactor*(@getClippedInput(k + 1) - @getClippedInput(k - 1))/2

	interpolate: (t) ->
		k = Math.floor t
		m = [(@getTangent k), (@getTangent k+1)] #get tangents
		p = [(@getClippedInput k), (@getClippedInput k+1)] #get points
		#Translate t to interpolate between k and k+1
		t -= k
		t2 = t*t #t^2
		t3 = t*t2 #t^3
		#Apply cubic hermite spline formula
		return (2*t3 - 3*t2 + 1)*p[0] + (t3 - 2*t2 + t)*m[0] + (-2*t3 + 3*t2)*p[1] + (t3 - t2)*m[1]

{sin, PI} = Math
sinc = (x) -> 
	if x is 0 then 1
	else sin(PI*x)/(PI*x)

makeLanczosWindow = (a) ->
	(x) -> sinc(x/a) #lanczos window

makeSincKernel = (window) ->
	(x) -> sinc(x)*window(x)

class SincFilterInterpolator extends AbstractInterpolator
	constructor: (array, config) ->
		super
		#Create the lanczos kernel function
		@a = config.sincFilterSize

		window = config.sincWindow
		throw 'No sincWindow provided' unless window?
		@kernel = makeSincKernel window

	interpolate: (t) ->
		k = Math.floor t
		#Convolve with Lanczos kernel
		sum = 0
		for n in [(k - @a + 1)..(k + @a)]
			sum += @kernel(t - n)*@getClippedInput(n)
		sum


#Extract a column from a two dimensional array
getColumn = (arr, i) -> (row[i] for row in arr)


#Take a function with one parameter and apply a scale factor to its parameter
makeScaledFunction = (f, baseScale, scaleRange) ->
	if scaleRange.join is '0,1'
		f #don't wrap the function unecessarily
	else 
		scaleFactor = baseScale/(scaleRange[1] - scaleRange[0])
		translation = scaleRange[0]
		(t) -> f scaleFactor*(t - translation)


getType = (x) -> Object::toString.call(x)[('[object '.length)...-1]

#Throw exception if input is not a number
validateNumber = (n) ->
	throw 'NaN in Smooth() input' if isNaN n
	throw 'Non-number in Smooth() input' unless getType(n) is 'Number'
	throw 'Infinity in Smooth() input' unless isFinite n
		

#Throw an exception if input is not a vector of numbers which is the correct length
validateVector = (v, dimension) ->
	throw 'Non-vector in Smooth() input' unless getType(v) is 'Array'
	throw 'Inconsistent dimension in Smooth() input' unless v.length is dimension
	validateNumber n for n in v

isValidNumber = (n) -> (getType(n) is 'Number') and isFinite(n) and not isNaN(n)

normalizeScaleTo = (s) ->
	invalidErr = "scaleTo param must be number or array of two numbers"
	switch getType s
		when 'Number'
			throw invalidErr unless isValidNumber s
			s = [0, s]
		when 'Array'
			throw invalidErr unless s.length is 2
			throw invalidErr unless isValidNumber(s[0]) and isValidNumber(s[1])
		else throw invalidErr
	return s

shallowCopy = (obj) ->
	copy = {}
	copy[k] = v for own k,v of obj
	copy

Smooth = (arr, config = {}) ->
	#Make a copy of the config object
	config = shallowCopy config
	#Alias 'period' to 'scaleTo'
	config.scaleTo ?= config.period

	#Alias lanczosFilterSize to sincFilterSize
	config.sincFilterSize ?= config.lanczosFilterSize

	config[k] ?= v for own k,v of defaultConfig #fill in defaults

	#Get the interpolator class according to the configuration
	interpolatorClasses = 
		nearest: NearestInterpolator
		linear: LinearInterpolator
		cubic: CubicInterpolator
		lanczos: SincFilterInterpolator #lanczos is a specific case of sinc filter
		sinc: SincFilterInterpolator


	interpolatorClass = interpolatorClasses[config.method]
	
	throw "Invalid method: #{config.method}" unless interpolatorClass?

	if config.method is 'lanczos'
		#Setup lanczos window
		config.sincWindow = makeLanczosWindow config.sincFilterSize


	#Make sure there's at least one element in the input array
	throw 'Array must have at least two elements' if arr.length < 2

	#See what type of data we're dealing with
	dataType = getType arr[0]

	smoothFunc = switch dataType
			when 'Number' #scalar
				#Validate all input if deep validation is on
				validateNumber n for n in arr if Smooth.deepValidation
				#Create the interpolator
				interpolator = new interpolatorClass arr, config
				#make function that runs the interpolator
				(t) -> interpolator.interpolate t

			when 'Array' # vector
				dimension = arr[0].length
				throw 'Vectors must be non-empty' unless dimension
				#Validate all input if deep validation is on
				validateVector v, dimension for v in arr if Smooth.deepValidation
				#Create interpolator for each column
				interpolators = (new interpolatorClass(getColumn(arr, i), config) for i in [0...dimension])
				#make function that runs the interpolators and puts them into an array
				(t) -> (interpolator.interpolate(t) for interpolator in interpolators)

			else throw "Invalid element type: #{dataType}"

	if config.scaleTo
		scaleRange = normalizeScaleTo config.scaleTo
		#Because periodic functions repeat, we scale the domain to extend to the beginning of the next cycle.
		if config.clip is Smooth.CLIP_PERIODIC
			baseScale = arr.length
		else #for other clipping types, we scale the domain to extend exactly to the end of the input array
			baseScale = arr.length - 1
		smoothFunc = makeScaledFunction smoothFunc, baseScale, scaleRange

	return smoothFunc


#Copy enums to Smooth
Smooth[k] = v for own k,v of Enum


Smooth.deepValidation = true

root = exports ? window
root.Smooth = Smooth
