/*
* SwiftLocation
* Easy and Efficent Location Tracker for Swift
*
* Created by:	Daniele Margutti
* Email:		hello@danielemargutti.com
* Web:			http://www.danielemargutti.com
* Twitter:		@danielemargutti
*
* Copyright © 2017 Daniele Margutti
*
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
* THE SOFTWARE.
*
*/


import Foundation
import CoreLocation
import MapKit

public enum HeadingObserver {
	public typealias onSuccess = ((_ request: HeadingRequest, _ heading: CLHeading) -> (Void))
	public typealias onError = ((_ request: HeadingRequest, _ error: Error) -> (Void))
	
	case onReceivedHeading(_: Context, _: onSuccess)
	case onErrorOccurred(_: Context, _: onError)
}

//MARK: - Heading Request

open class HeadingRequest: Request {
	
	/// Callback to call when request's state did change
	open var onStateChange: ((_ old: RequestState, _ new: RequestState) -> (Void))?
	
	/// Registered callbacks
	fileprivate var registeredCallbacks: [HeadingObserver] = []
	
	/// This represent the current state of the Request
	internal var _previousState: RequestState = .idle
	internal(set) var _state: RequestState = .idle {
		didSet {
			if _previousState != _state {
				onStateChange?(_previousState,_state)
				_previousState = _state
			}
		}
	}
	open var state: RequestState {
		get {
			return self._state
		}
	}
	
	/// The minimum angular change (measured in degrees) required to generate new heading events.
	/// If nil you will receive any new measured change without any filter.
	open var filter: CLLocationDegrees? {
		didSet {
			Location.updateHeadingServices()
		}
	}
	
	/// Assigned request name, used for your own convenience
	open var name: String?
	
	/// Cancel request if an error occours. By default is `false`.
	open var cancelOnError: Bool = false
	
	/// Previous measured heading
	fileprivate var previousHeading: CLHeading? = nil
	
	/// `true` if request is on location queue
	open var isInQueue: Bool {
		return Location.isQueued(self) == true
	}
	
	/// Request type of CLLocationManager authorization
	open var requiredAuth: Authorization {
		return .none
	}
	
	/// Is this a background request?
	open var isBackgroundRequest: Bool {
		return false
	}
	
	/// Description of the request
	open var description: String {
		let name = (self.name ?? self.identifier)
		return "[HEAD:\(name)] - Filter=\(self.filter) meters. (Status=\(self.state), Queued=\(self.isInQueue))"
	}
	
	/// Initialize a new heading request
	///
	/// - Parameters:
	///   - filter: The minimum angular change (measured in degrees) required to generate new heading events.
	///   - success: handler called to receive new heading measures
	///   - failure: handler called to receive errors
	public init(name: String? = nil, filter: CLLocationDegrees? = nil,
	            success: @escaping HeadingObserver.onSuccess, failure: @escaping HeadingObserver.onError) throws {
		guard CLLocationManager.headingAvailable() else {
			throw LocationError.serviceNotAvailable
		}
		self.name = name
		self.filter = filter
		self.add(HeadingObserver.onReceivedHeading(.main, success))
		self.add(HeadingObserver.onErrorOccurred(.main, failure))
	}

	open func add(_ callback: HeadingObserver?) {
		guard let callback = callback else { return }
		self.registeredCallbacks.append(callback)
	}
	
	/// Resume a paused request or start it
	open func resume() {
		Location.start(self)
	}
	
	/// Pause a running request.
	///
	/// - Returns: `true` if request is paused, `false` otherwise.
	open func pause() {
		Location.pause(self)
	}
	
	/// Cancel request and remove it from queue.
	open func cancel() {
		Location.cancel(self)
	}
	
	open func onPause() {
		
	}
	
	open func onResume() {
		
	}
	
	open func onCancel() {
		
	}

	
	/// Returns a Boolean value indicating whether two values are equal.
	///
	/// Equality is the inverse of inequality. For any values `a` and `b`,
	/// `a == b` implies that `a != b` is `false`.
	///
	/// - Parameters:
	///   - lhs: A value to compare.
	///   - rhs: Another value to compare.
	public static func ==(lhs: HeadingRequest, rhs: HeadingRequest) -> Bool {
		return lhs.hashValue == rhs.hashValue
	}
	
	/// Unique identifier of the request
	fileprivate var identifier = UUID().uuidString
	
	/// Hash value for Hashable protocol
	open var hashValue: Int {
		return identifier.hash
	}
	
	
	/// Dispatch error to callbacks and remove request from queue if `cancelOnError` is `true`.
	///
	/// - Parameter error: error to dispatch
	open func dispatch(_ error: Error) {
		self.registeredCallbacks.forEach {
			if case .onErrorOccurred(let context, let handler) = $0 {
				context.queue.async { handler(self,error) }
			}
		}
		
		if self.cancelOnError == true { // remove from main location queue
			self.cancel()
			self._state = .failed(error)
		}
	}
	
	
	/// Dispatch new heading to callbacks
	///
	/// - Parameter heading: heading
	internal func dispatch(_ heading: CLHeading) {
		defer {
			self.previousHeading = heading
		}
		guard self.filterIsChangedEnough(heading) else { return }
		self.registeredCallbacks.forEach {
			if case .onReceivedHeading(let context, let handler) = $0 {
				context.queue.async { handler(self,heading) }
			}
		}
	}
	
	
	/// `true` if filter is changed enough.
	///
	/// - Parameter heading: heading to check
	/// - Returns: `true` if new heading can be dispatched to registered callbacks
	fileprivate func filterIsChangedEnough(_ heading: CLHeading) -> Bool {
		guard let prevHeading = self.previousHeading, let filter = self.filter else {
			return true
		}
		return abs(abs(prevHeading.trueHeading) - abs(heading.trueHeading)) > filter
	}

}
