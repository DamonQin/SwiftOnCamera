//
//  SOController.swift
//  SwiftOnCamera
//
//  Created by QinChong on 15/3/11.
//  Copyright (c) 2015年 Damon Qin. All rights reserved.
//

import UIKit
import Foundation
import AVFoundation
import AssetsLibrary

/*============================== Preview View ================================*/
private class SOCPreviewView: UIView {
    
    var session: AVCaptureSession? {
        get {
            return (self.layer as AVCaptureVideoPreviewLayer).session
        }
        set {
            (self.layer as AVCaptureVideoPreviewLayer).session = newValue
        }
    }
    
    override class func layerClass() -> AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
}

/*============================= SOC Controller ===============================*/
private var CapturingStillImageContext = "CapturingStillImageContext"
private var SessionRunningAndDeviceAuthorizedContext = "SessionRunningAndDeviceAuthorizedContext"

class SOController: UIViewController {
    //MARK: - Session management
    private var sessionQueue: dispatch_queue_t?
    private var session: AVCaptureSession?
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var stillImageOutput: AVCaptureStillImageOutput?
    
    //MARK: - Utilities
    private var backgroundRecordingID: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid
    private var deviceAuthorized: Bool = false
    private var lockInterfaceRotation: Bool = false
    private var runtimeErrorHandingObserver: AnyObject?
    private var sessionRunningAndDeviceAuthorized: Bool {
        get {
            //Mark: http://stackoverflow.com/questions/25648021/optional-type-t11-cannot-be-used-as-a-boolean-test-for-nil-instead-sinc
            return (self.session?.running != nil && self.deviceAuthorized)
        }
    }
    
    private var previewView = SOCPreviewView()

    //MARK: -
    override func viewDidLoad() {
        super.viewDidLoad()
        
        previewView.setTranslatesAutoresizingMaskIntoConstraints(false)
        view.addSubview(previewView)
        view.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("H:|-p-[p]-p-|", options: NSLayoutFormatOptions.DirectionLeadingToTrailing, metrics: ["p": 0], views: ["p" : self.previewView]))
        view.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("V:|-[p]-|", options: NSLayoutFormatOptions.DirectionLeadingToTrailing, metrics: nil, views: ["p" : self.previewView]))
        
        var tapGesture = UITapGestureRecognizer(target: self, action: "focusAndExposeTap:")
        tapGesture.delaysTouchesEnded = false
        tapGesture.numberOfTapsRequired = 1
        previewView.addGestureRecognizer(tapGesture)
        
        var sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL)
        
        var session = AVCaptureSession()
        session.beginConfiguration()
        self.session = session
        self.previewView.session = session
        
        self.checkDeviceAuthorizationStatus()
        
        self.sessionQueue = sessionQueue
        dispatch_async(sessionQueue, { () -> Void in
            self.backgroundRecordingID = UIBackgroundTaskInvalid
            var error: NSError? = nil
            var videoDevice = SOController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: AVCaptureDevicePosition.Back)
            var videoDeviceInput = AVCaptureDeviceInput(device: videoDevice, error: &error)
            if error != nil {
                println("Video Device Input Error: \(error)")
            }
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    var orientation = AVCaptureVideoOrientation(rawValue: self.interfaceOrientation.rawValue)!
                    (self.previewView.layer as AVCaptureVideoPreviewLayer).connection.videoOrientation = orientation
                })
            }
            
            var stillImageOutput = AVCaptureStillImageOutput()
            if session.canAddOutput(stillImageOutput) {
                stillImageOutput.outputSettings = [AVVideoCodecKey : AVVideoCodecJPEG]
                session.addOutput(stillImageOutput)
                self.stillImageOutput = stillImageOutput
            }
        })
        session.commitConfiguration()
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        dispatch_async(self.sessionQueue, { () -> Void in
            self.addObserver(self, forKeyPath: "SessionRunningAndDeviceAuthorizedContext", options: NSKeyValueObservingOptions.Old | NSKeyValueObservingOptions.New, context: &SessionRunningAndDeviceAuthorizedContext)
            self.addObserver(self.stillImageOutput!, forKeyPath: "capturingStillImage", options: NSKeyValueObservingOptions.Old | NSKeyValueObservingOptions.New, context: &CapturingStillImageContext)
            
            NSNotificationCenter.defaultCenter().addObserver(self, selector: "subjectAreaDidChange", name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: self.videoDeviceInput?.device)
            
            weak var weakSelf = self
            self.runtimeErrorHandingObserver = NSNotificationCenter.defaultCenter().addObserverForName(AVCaptureSessionRuntimeErrorNotification, object: self.session, queue: nil, usingBlock: { (notification) -> Void in
                var strongSelf = weakSelf!
                dispatch_async(strongSelf.sessionQueue, { () -> Void in
                    if let strongSession = strongSelf.session {
                        strongSession.startRunning()
                    }
                })
            })
            
            self.session?.startRunning()
        })
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        
        dispatch_async(self.sessionQueue, { () -> Void in
            if let sess = self.session {
                sess.stopRunning()
                
                NSNotificationCenter.defaultCenter().removeObserver(self, name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: self.videoDeviceInput?.device)
                NSNotificationCenter.defaultCenter().removeObserver(self.runtimeErrorHandingObserver!)
                
                self.removeObserver(self, forKeyPath: "SessionRunningAndDeviceAuthorizedContext", context: &SessionRunningAndDeviceAuthorizedContext)
                self.removeObserver(self.stillImageOutput!, forKeyPath: "capturingStillImage", context: &CapturingStillImageContext)
            }
        })
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    
    override func shouldAutorotate() -> Bool {
        return !self.lockInterfaceRotation
    }
    
    override func supportedInterfaceOrientations() -> Int {
        return Int(UIInterfaceOrientationMask.All.rawValue)
    }
    
    override func willRotateToInterfaceOrientation(toInterfaceOrientation: UIInterfaceOrientation, duration: NSTimeInterval) {
        (self.previewView.layer as AVCaptureVideoPreviewLayer).connection.videoOrientation = AVCaptureVideoOrientation(rawValue: toInterfaceOrientation.rawValue)!
    }
    
    override func observeValueForKeyPath(keyPath: String, ofObject object: AnyObject, change: [NSObject : AnyObject], context: UnsafeMutablePointer<Void>) {
        if context == &CapturingStillImageContext {
            if let isCapturingStillImage = change[NSKeyValueChangeNewKey]?.boolValue {
                runStillImageCaptureAnimation()
            }
        } else if context == &SessionRunningAndDeviceAuthorizedContext {
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                if let isRunning = change[NSKeyValueChangeNewKey]?.boolValue {
                    //TODO: Enable Action Buttons
                } else {
                    //TODO: Disable Action Buttons
                }
            })
        } else {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
    }

    //MARK: - Device Configuration
    private class func deviceWithMediaType(mediaType: String, preferringPosition:AVCaptureDevicePosition) -> AVCaptureDevice? {
        var devices = AVCaptureDevice.devicesWithMediaType(mediaType)
        if var captureDevice = devices.first as? AVCaptureDevice {
            for device in devices {
                if device.position == preferringPosition {
                    captureDevice = device as AVCaptureDevice
                    break
                }
            }
            
            return captureDevice
        } else {
            return nil
        }
    }
    
    private class func setFlashMode(flashMode: AVCaptureFlashMode, forDevice device: AVCaptureDevice) {
        if device.hasFlash && device.isFlashModeSupported(flashMode) {
            var error: NSError? = nil
            if device.lockForConfiguration(&error) {
                device.flashMode = flashMode
                device.unlockForConfiguration()
            } else {
                println("Set flash mode error: \(error)")
            }
        }
    }
    
    private func focusWithMode(focusMode: AVCaptureFocusMode, exposeMode: AVCaptureExposureMode, atDevicePoint point: CGPoint, monitorSubjectAreaChange: Bool) {
        dispatch_async(self.sessionQueue, { () -> Void in
            if let device = self.videoDeviceInput?.device {
                var error: NSError? = nil
                if device.lockForConfiguration(&error) {
                    if device.focusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                        device.focusMode = focusMode
                        device.focusPointOfInterest = point
                    }
                    if device.exposurePointOfInterestSupported && device.isExposureModeSupported(exposeMode) {
                        device.exposureMode = exposeMode
                        device.exposurePointOfInterest = point
                    }
                    
                    device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                    device.unlockForConfiguration()
                } else {
                    println("Focus or Expose Error: \(error)")
                }
            }
        })
    }
    
    //MARK: - UI
    private func runStillImageCaptureAnimation() {
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            self.previewView.layer.opacity = 0.0
            UIView.animateWithDuration(0.25, animations: { () -> Void in
                self.previewView.layer.opacity = 1.0
            })
        })
    }
    
    private func checkDeviceAuthorizationStatus() {
        AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo, completionHandler: { (granted) -> Void in
            if granted {
                self.deviceAuthorized = true
            } else {
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    var alert = UIAlertController(title: "Opps!", message: "Seem to do not have permission to use the Camera, please change privacy settings.", preferredStyle: .Alert)
                    var action = UIAlertAction(title: "OK", style: .Default, handler: { (alertAction: UIAlertAction!) -> Void in
                        //TODO: How?
                    })
                    alert.addAction(action)
                    self.presentViewController(alert, animated: true, completion: nil)
                    self.deviceAuthorized = false
                })
            }
        })
    }
    
    func focusAndExposeTap(gesture: UIGestureRecognizer) {
        var devicePoint = (self.previewView.layer as AVCaptureVideoPreviewLayer).captureDevicePointOfInterestForPoint(gesture.locationInView(gesture.view))
        self.focusWithMode(AVCaptureFocusMode.AutoFocus, exposeMode: AVCaptureExposureMode.AutoExpose, atDevicePoint: devicePoint, monitorSubjectAreaChange: true)
        
        //TODO: Here maybe have a bug. I will fix in the future.
        self.focusWithMode(AVCaptureFocusMode.AutoFocus, exposeMode: AVCaptureExposureMode.AutoExpose, atDevicePoint: devicePoint, monitorSubjectAreaChange: true)
    }
    
    func subjectAreaDidChange() {
        var devicePoint = CGPoint(x: 0.5, y: 0.5)
        self.focusWithMode(AVCaptureFocusMode.ContinuousAutoFocus, exposeMode: AVCaptureExposureMode.ContinuousAutoExposure, atDevicePoint: devicePoint, monitorSubjectAreaChange: false)
    }
    
    //MARK: - Actions
    func changeCamera() {
        //TODO: Disable Action Buttons
        dispatch_async(self.sessionQueue, { () -> Void in
            if var currentVideoDevice = self.videoDeviceInput?.device {
                var preferredPosition = AVCaptureDevicePosition.Unspecified
                var currentPosition = currentVideoDevice.position
                
                switch currentPosition {
                case AVCaptureDevicePosition.Front:
                    preferredPosition = AVCaptureDevicePosition.Back
                case AVCaptureDevicePosition.Back:
                    preferredPosition = AVCaptureDevicePosition.Front
                case AVCaptureDevicePosition.Unspecified:
                    preferredPosition = AVCaptureDevicePosition.Back
                }
                
                self.session!.beginConfiguration()
                if var videoDevice = SOController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: preferredPosition) {
                    var videoDeviceInput = AVCaptureDeviceInput(device: videoDevice, error: nil)
                    self.session!.removeInput(self.videoDeviceInput)
                    if self.session!.canAddInput(videoDeviceInput) {
                        NSNotificationCenter.defaultCenter().removeObserver(self, name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: currentVideoDevice)
                        SOController.setFlashMode(AVCaptureFlashMode.Auto, forDevice: videoDevice)
                        NSNotificationCenter.defaultCenter().addObserver(self, selector: "", name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: videoDevice)
                        self.session!.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        self.session?.addInput(self.videoDeviceInput)
                    }
                }
                self.session?.commitConfiguration()
                
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    //TODO: Enable Action Buttons
                })
            }
        })
    }
    
    func snapStillImage() {
        dispatch_async(self.sessionQueue, { () -> Void in
            var videoOrientation = (self.previewView.layer as AVCaptureVideoPreviewLayer).connection.videoOrientation
            self.stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo).videoOrientation = videoOrientation
            
            SOController.setFlashMode(AVCaptureFlashMode.Auto, forDevice: self.videoDeviceInput!.device)
            
            self.stillImageOutput!.captureStillImageAsynchronouslyFromConnection(self.stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo), completionHandler: { (imageDataSampleBuffer: CMSampleBuffer!, error: NSError!) -> Void in
                if error == nil {
                    var imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                    var image = UIImage(data: imageData)!
                    
                    var orientation = ALAssetOrientation(rawValue: image.imageOrientation.rawValue)!
                    ALAssetsLibrary().writeImageToSavedPhotosAlbum(image.CGImage, orientation: orientation, completionBlock: nil)
                } else {
                    println("Capture Image Error: \(error)")
                }
            })
        })
    }
}
