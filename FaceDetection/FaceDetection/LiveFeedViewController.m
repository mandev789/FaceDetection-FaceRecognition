//
//  LiveFeedViewController.m
//  FaceDetection
/**///////////////////////////////////////////////////////////////////////////////////////
    //
    //  IMPORTANT: READ BEFORE DOWNLOADING, COPYING, INSTALLING OR USING.
    //
    //  By downloading, copying, installing or using the software you agree to this license.
    //  If you do not agree to this license, do not download, install,
    //  copy or use the software.
    //
    //
    //                        License Agreement
    //                For Open Source Codebase that follows
    //
    // Copyright (C) 2011, Praveen K Jha, Praveen K Jha., all rights reserved.
    // Third party copyrights are property of their respective owners.
    //
    // Redistribution and use in source and binary forms, with or without modification,
    // are permitted provided that the following conditions are met:
    //
    //   * Redistribution's of source code must retain the above copyright notice,
    //     this list of conditions and the following disclaimer.
    //
    //   * Redistribution's in binary form must reproduce the above copyright notice,
    //     this list of conditions and the following disclaimer in the documentation
    //     and/or other materials provided with the distribution.
    //
    //   * The name of the company may not be used to endorse or promote products
    //     derived from this software without specific prior written permission.
    //
    // This software is provided by the copyright holders and contributors "as is" and
    // any express or implied warranties, including, but not limited to, the implied
    // warranties of merchantability and fitness for a particular purpose are disclaimed.
    // In no event shall the owning company or contributors be liable for any direct,
    // indirect, incidental, special, exemplary, or consequential damages
    // (including, but not limited to, procurement of substitute goods or services;
    // loss of use, data, or profits; or business interruption) however caused
    // and on any theory of liability, whether in contract, strict liability,
    // or tort (including negligence or otherwise) arising in any way out of
    // the use of this software, even if advised of the possibility of such damage.
    //
    //**/


#import "LiveFeedViewController.h"
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <AssertMacros.h>
#import <AssetsLibrary/AssetsLibrary.h>

static CGFloat DegreesToRadians(CGFloat degrees) {return degrees * M_PI / 180;};

@interface LiveFeedViewController ()
{
    int numberOfSubjects;
    int fileCount;
}
@property (nonatomic) BOOL isUsingFrontFacingCamera;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic) dispatch_queue_t videoDataOutputQueue;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;

@property (nonatomic, strong) UIImage *borderImage;
@property (nonatomic, strong) CIDetector *faceDetector;


- (void)setupAVCapture;
- (void)teardownAVCapture;
- (void)drawFaces:(NSArray *)features 
      forVideoBox:(CGRect)videoBox 
      orientation:(UIDeviceOrientation)orientation;


@end

@implementation LiveFeedViewController

@synthesize videoDataOutput = _videoDataOutput;
@synthesize videoDataOutputQueue = _videoDataOutputQueue;

@synthesize borderImage = _borderImage;
@synthesize previewView = _previewView;
@synthesize previewLayer = _previewLayer;

@synthesize faceDetector = _faceDetector;

@synthesize isUsingFrontFacingCamera = _isUsingFrontFacingCamera;

@synthesize mode=_mode;

- (void)setupAVCapture
{
    numberOfSubjects =1;
    fileCount =1;
	NSError *error = nil;
	
	AVCaptureSession *session = [[AVCaptureSession alloc] init];
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone){
	    [session setSessionPreset:AVCaptureSessionPreset640x480];
	} else {
	    [session setSessionPreset:AVCaptureSessionPresetPhoto];
	}
    
    // Select a video device, make an input
	AVCaptureDevice *device;
	
    AVCaptureDevicePosition desiredPosition = AVCaptureDevicePositionFront;
	
    // find the front facing camera
	for (AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
		if ([d position] == desiredPosition) {
			device = d;
            self.isUsingFrontFacingCamera = YES;
			break;
		}
	}
    // fall back to the default camera.
    if( nil == device )
    {
        self.isUsingFrontFacingCamera = NO;
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    
    // get the input device
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    
	if( !error ) {
        
        // add the input to the session
        if ( [session canAddInput:deviceInput] ){
            [session addInput:deviceInput];
        }
        
        
        // Make a video data output
        self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
        
        // we want BGRA, both CoreGraphics and OpenGL work well with 'BGRA'
        NSDictionary *rgbOutputSettings = [NSDictionary dictionaryWithObject:
                                           [NSNumber numberWithInt:kCMPixelFormat_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
        [self.videoDataOutput setVideoSettings:rgbOutputSettings];
        [self.videoDataOutput setAlwaysDiscardsLateVideoFrames:YES]; // discard if the data output queue is blocked
        
        // create a serial dispatch queue used for the sample buffer delegate
        // a serial dispatch queue must be used to guarantee that video frames will be delivered in order
        // see the header doc for setSampleBufferDelegate:queue: for more information
        self.videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
        [self.videoDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];
        
        if ( [session canAddOutput:self.videoDataOutput] ){
            [session addOutput:self.videoDataOutput];
        }
        
        // get the output for doing face detection.
        [[self.videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:YES]; 

        self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
        self.previewLayer.backgroundColor = [[UIColor blackColor] CGColor];
        self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        
        CALayer *rootLayer = [self.previewView layer];
        [self.previewView setTag:9999];
        [rootLayer setMasksToBounds:YES];
        [self.previewLayer setFrame:[rootLayer bounds]];
        [rootLayer addSublayer:self.previewLayer];
        [session startRunning];
        
    }
	session = nil;
	if (error) {
		UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:
                            [NSString stringWithFormat:@"Failed with error %d", (int)[error code]]
                                               message:[error localizedDescription]
										      delegate:nil 
								     cancelButtonTitle:@"Dismiss" 
								     otherButtonTitles:nil];
		[alertView show];
		[self teardownAVCapture];
	}
}

//! Switches from rear to front camera and vice-versa.
-(void) switchSessions:(id)sender//:(BOOL)isRear
{
	if([self.previewLayer.session isRunning])
	{
        [self.previewLayer.session stopRunning];
        [self.previewLayer.session removeInput:[self.previewLayer.session.inputs objectAtIndex:0]];
    }
    AVCaptureDevice *device;
    AVCaptureDevicePosition desiredPosition = self.isUsingFrontFacingCamera?AVCaptureDevicePositionBack:AVCaptureDevicePositionFront;

    // find the front facing camera
	for (AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo])
    {
		if ([d position] == desiredPosition)
        {
			device = d;
            self.isUsingFrontFacingCamera = !self.isUsingFrontFacingCamera;
			break;
		}
	}
    // fall back to the default camera.
    if( nil == device )
    {
        self.isUsingFrontFacingCamera = !self.isUsingFrontFacingCamera;
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    NSError *error;
    // get the input device
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];

    if( !error )
    {

        // add the input to the session
        if ( [self.previewLayer.session canAddInput:deviceInput] )
        {
            [self.previewLayer.session addInput:deviceInput];
        }
    }
    [self.previewLayer.session startRunning];
}

// clean up capture setup
- (void)teardownAVCapture
{
	self.videoDataOutput = nil;
	if (self.videoDataOutputQueue) {
		dispatch_release(self.videoDataOutputQueue);
    }
	[self.previewLayer removeFromSuperlayer];
	self.previewLayer = nil;
}


// utility routine to display error aleart if takePicture fails
- (void)displayErrorOnMainQueue:(NSError *)error withMessage:(NSString *)message
{
	dispatch_async(dispatch_get_main_queue(), ^(void) {
		UIAlertView *alertView = [[UIAlertView alloc] 
                initWithTitle:[NSString stringWithFormat:@"%@ (%d)", message, (int)[error code]]
                      message:[error localizedDescription]
				     delegate:nil 
		    cancelButtonTitle:@"Dismiss" 
		    otherButtonTitles:nil];
        [alertView show];
	});
}

-(void)doneLiveFeed:(id)sender
{
    [self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)trainForRecognition:(id)sender
{
    if (numberOfSubjects <=0)
    {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
        NSString *userDir = [baseDir stringByAppendingPathComponent:@"TrainingSetUser1"];

        [[NSFileManager defaultManager] removeItemAtPath:userDir error:nil];
    }
    fileCount=1;
    [((UIButton*)[self.view viewWithTag:10001]) setTitle:@"Training..." forState:UIControlStateNormal];
    numberOfSubjects++;
    self.mode = Training;
}

- (void)recognize:(id)sender
{
    if (numberOfSubjects <=2) {
		UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:
                                  @"Insufficient training set!"
                                                            message:@"Please train at least 2-3 times!"
                                                           delegate:nil
                                                  cancelButtonTitle:@"Got it!"
                                                  otherButtonTitles:nil];
		[alertView show];
        return;
    }
    [((UIButton *)[self.view viewWithTag:10002]) setTitle:@"Hold on..." forState:UIControlStateNormal];
    // Overridden?
    self.mode = Recognition;
    [self.previewLayer.session stopRunning];
}

-(void) addBackButton
{
    UIButton *btn = [[UIButton alloc] initWithFrame:CGRectMake(self.view.frame.origin.x +5, self.view.frame.origin.y + 60, 50, 40)];
    [btn setTitle:@"Done" forState:UIControlStateNormal];
    [btn setTag:10000];
    [self.view addSubview:btn];
    [self.view setBackgroundColor:[UIColor greenColor]];
    [btn setBackgroundColor:[UIColor redColor]];
    [btn addTarget:self action:@selector(doneLiveFeed:) forControlEvents:UIControlEventTouchUpInside];

    if (self.mode != Detection)
    {
        // Train/recognise button
        UIButton *btnTrain = [[UIButton alloc] initWithFrame:CGRectMake(self.view.frame.origin.x +60, self.view.frame.origin.y + 60, 80, 40)];
        [btnTrain setTitle:@"Training..." forState:UIControlStateNormal];
        [btnTrain setTag:10001];
        [self.view addSubview:btnTrain];
        [btnTrain setBackgroundColor:[UIColor redColor]];
        [btnTrain addTarget:self action:@selector(trainForRecognition:) forControlEvents:UIControlEventTouchUpInside];

        UIButton *btnRecognise = [[UIButton alloc] initWithFrame:CGRectMake(self.view.frame.origin.x +145, self.view.frame.origin.y + 60, 90, 40)];
        [btnRecognise setTitle:@"Recognize" forState:UIControlStateNormal];
        [btnRecognise setTag:10002];
        [self.view addSubview:btnRecognise];
        [btnRecognise setBackgroundColor:[UIColor redColor]];
        [btnRecognise addTarget:self action:@selector(recognize:) forControlEvents:UIControlEventTouchUpInside];
    }
    
    UIButton *btnSwitch = [[UIButton alloc] initWithFrame:CGRectMake(self.view.frame.origin.x +240, self.view.frame.origin.y + 60, 60, 40)];
    [btnSwitch setTitle:@"Switch" forState:UIControlStateNormal];
    [btnSwitch setTag:10003];
    [self.view addSubview:btnSwitch];
    [btnSwitch setBackgroundColor:[UIColor redColor]];
    [btnSwitch addTarget:self action:@selector(switchSessions:) forControlEvents:UIControlEventTouchUpInside];

}


// find where the video box is positioned within the preview layer based on the video size and gravity
+ (CGRect)videoPreviewBoxForGravity:(NSString *)gravity 
                          frameSize:(CGSize)frameSize 
                       apertureSize:(CGSize)apertureSize
{
    CGFloat apertureRatio = apertureSize.height / apertureSize.width;
    CGFloat viewRatio = frameSize.width / frameSize.height;
    
    CGSize size = CGSizeZero;
    if ([gravity isEqualToString:AVLayerVideoGravityResizeAspectFill]) {
        if (viewRatio > apertureRatio) {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        } else {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResizeAspect]) {
        if (viewRatio > apertureRatio) {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        } else {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResize]) {
        size.width = frameSize.width;
        size.height = frameSize.height;
    }
	
	CGRect videoBox;
	videoBox.size = size;
	if (size.width < frameSize.width)
		videoBox.origin.x = (frameSize.width - size.width) / 2;
	else
		videoBox.origin.x = (size.width - frameSize.width) / 2;
	
	if ( size.height < frameSize.height )
		videoBox.origin.y = (frameSize.height - size.height) / 2;
	else
		videoBox.origin.y = (size.height - frameSize.height) / 2;
    
	return videoBox;
}

// called asynchronously as the capture output is capturing sample buffers, this method asks the face detector
// to detect features and for each draw the green border in a layer and set appropriate orientation
- (void)drawFaces:(NSArray *)features 
      forVideoBox:(CGRect)clearAperture 
orientation:(UIDeviceOrientation)orientation
            image:(CIImage*)ciImage
{
	NSArray *sublayers = [NSArray arrayWithArray:[self.previewLayer sublayers]];
	NSInteger sublayersCount = [sublayers count], currentSublayer = 0;
	NSInteger featuresCount = [features count], currentFeature = 0;
	
	[CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
	
	// hide all the face layers
	for ( CALayer *layer in sublayers ) {
		if ( [[layer name] isEqualToString:@"FaceLayer"] )
			[layer setHidden:YES];
	}
	
	if ( featuresCount == 0 ) {
		[CATransaction commit];
		return; // early bail.
	}
    
	CGSize parentFrameSize = [self.previewView frame].size;
	NSString *gravity = [self.previewLayer videoGravity];
	BOOL isMirrored = [self.previewLayer isMirrored];
	CGRect previewBox = [LiveFeedViewController videoPreviewBoxForGravity:gravity 
                                                        frameSize:parentFrameSize 
                                                     apertureSize:clearAperture.size];

    NSArray *arr = [self.view subviews];
    for (int i=arr.count-1; i>=0; i--) {
        UIView *v = [arr objectAtIndex:i];
        if (v.tag !=9999 && v.tag >10003)
            [v removeFromSuperview];
    }
    
	for ( CIFaceFeature *ff in features ) {
		// find the correct position for the square layer within the previewLayer
		// the feature box originates in the bottom left of the video frame.
		// (Bottom right if mirroring is turned on)
		CGRect faceRect = [ff bounds];
        
		// flip preview width and height
		CGFloat temp = faceRect.size.width;
		faceRect.size.width = faceRect.size.height;
		faceRect.size.height = temp;
		temp = faceRect.origin.x;
		faceRect.origin.x = faceRect.origin.y;
		faceRect.origin.y = temp;
		// scale coordinates so they fit in the preview box, which may be scaled
		CGFloat widthScaleBy = previewBox.size.width / clearAperture.size.height;
		CGFloat heightScaleBy = previewBox.size.height / clearAperture.size.width;
		faceRect.size.width *= widthScaleBy;
		faceRect.size.height *= heightScaleBy;
		faceRect.origin.x *= widthScaleBy;
		faceRect.origin.y *= heightScaleBy;
        
		if ( isMirrored )
			faceRect = CGRectOffset(faceRect, previewBox.origin.x + previewBox.size.width - faceRect.size.width - (faceRect.origin.x * 2), previewBox.origin.y);
		else
			faceRect = CGRectOffset(faceRect, previewBox.origin.x, previewBox.origin.y);
		
		CALayer *featureLayer = nil;
        CALayer *faceRectLayer = nil;
		
		// re-use an existing layer if possible
		while ( (!featureLayer || !faceRectLayer) && (currentSublayer < sublayersCount) ) {
			CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
			if ( [[currentLayer name] isEqualToString:@"FaceLayer"] ) {
				featureLayer = currentLayer;
				[currentLayer setHidden:NO];
			}
			if ( [[currentLayer name] isEqualToString:@"FaceRectLayer"] ) {
				faceRectLayer = currentLayer;
				[currentLayer setHidden:NO];
			}

		}

        if (self.mode == Detection)
        {
            // create a new one if necessary
            if ( !featureLayer ) {
                featureLayer = [[CALayer alloc]init];
                featureLayer.contents = (id)self.borderImage.CGImage;
                [featureLayer setName:@"FaceLayer"];
                [self.previewLayer addSublayer:featureLayer];
                featureLayer = nil;
            }
            [featureLayer setFrame:faceRect];
            
            switch (orientation) {
                case UIDeviceOrientationPortrait:
                    [featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
                    break;
                case UIDeviceOrientationPortraitUpsideDown:
                    [featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
                    break;
                case UIDeviceOrientationLandscapeLeft:
                    [featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(90.))];
                    break;
                case UIDeviceOrientationLandscapeRight:
                    [featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(-90.))];
                    break;
                case UIDeviceOrientationFaceUp:
                case UIDeviceOrientationFaceDown:
                default:
                    break; // leave the layer in its last known orientation
            }
        }
        else if (!(featureLayer.frame.size.width == CGRectZero.size.width))
            [featureLayer setFrame:CGRectZero];

        if (!faceRectLayer)
        {
            // create a UIView using the bounds of the face
            UIView* faceView = [[UIView alloc] initWithFrame:faceRect];

            // add a border around the newly created UIView
            faceView.layer.borderWidth = 1;
            [faceView.layer setName:@"FaceRectLayer"];
            faceView.layer.borderColor = [[UIColor redColor] CGColor];
            [self.previewLayer addSublayer:faceView.layer];
            faceRectLayer =nil;
        }
        [faceRectLayer setFrame:faceRect];

        if (self.mode !=Detection)
        {
            CGRect grayScaleFace =[ff bounds];
            grayScaleFace = CGRectMake(grayScaleFace.origin.x, grayScaleFace.origin.y -10, grayScaleFace.size.width, grayScaleFace.size.height+10);
            [self saveImage:[self imageFromRect:grayScaleFace image:ciImage]];
        }
		currentFeature++;
	}
	
	[CATransaction commit];
}

- (NSNumber *) exifOrientation: (UIDeviceOrientation) orientation
{
	int exifOrientation;
    /* kCGImagePropertyOrientation values
     The intended display orientation of the image. If present, this key is a CFNumber value with the same value as defined
     by the TIFF and EXIF specifications -- see enumeration of integer constants. 
     The value specified where the origin (0,0) of the image is located. If not present, a value of 1 is assumed.
     
     used when calling featuresInImage: options: The value for this key is an integer NSNumber from 1..8 as found in kCGImagePropertyOrientation.
     If present, the detection will be done based on that orientation but the coordinates in the returned features will still be based on those of the image. */
    
	enum {
		PHOTOS_EXIF_0ROW_TOP_0COL_LEFT			= 1, //   1  =  0th row is at the top, and 0th column is on the left (THE DEFAULT).
		PHOTOS_EXIF_0ROW_TOP_0COL_RIGHT			= 2, //   2  =  0th row is at the top, and 0th column is on the right.  
		PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT      = 3, //   3  =  0th row is at the bottom, and 0th column is on the right.  
		PHOTOS_EXIF_0ROW_BOTTOM_0COL_LEFT       = 4, //   4  =  0th row is at the bottom, and 0th column is on the left.  
		PHOTOS_EXIF_0ROW_LEFT_0COL_TOP          = 5, //   5  =  0th row is on the left, and 0th column is the top.  
		PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP         = 6, //   6  =  0th row is on the right, and 0th column is the top.  
		PHOTOS_EXIF_0ROW_RIGHT_0COL_BOTTOM      = 7, //   7  =  0th row is on the right, and 0th column is the bottom.  
		PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM       = 8  //   8  =  0th row is on the left, and 0th column is the bottom.  
	};
	
	switch (orientation) {
		case UIDeviceOrientationPortraitUpsideDown:  // Device oriented vertically, home button on the top
			exifOrientation = PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM;
			break;
		case UIDeviceOrientationLandscapeLeft:       // Device oriented horizontally, home button on the right
			if (self.isUsingFrontFacingCamera)
				exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT;
			else
				exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT;
			break;
		case UIDeviceOrientationLandscapeRight:      // Device oriented horizontally, home button on the left
			if (self.isUsingFrontFacingCamera)
				exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT;
			else
				exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT;
			break;
		case UIDeviceOrientationPortrait:            // Device oriented vertically, home button on the bottom
		default:
			exifOrientation = PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP;
			break;
	}
    return [NSNumber numberWithInt:exifOrientation];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput 
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer 
       fromConnection:(AVCaptureConnection *)connection
{	
	// get the image
	CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
	CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
	CIImage *ciImage = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer 
                                                      options:(__bridge NSDictionary *)attachments];
	if (attachments) {
		CFRelease(attachments);
    }
    
    // make sure your device orientation is not locked.
	UIDeviceOrientation curDeviceOrientation = [[UIDevice currentDevice] orientation];
    
	NSDictionary *imageOptions = nil;
    
	imageOptions = [NSDictionary dictionaryWithObject:[self exifOrientation:curDeviceOrientation]
                                               forKey:CIDetectorImageOrientation];
    
	NSArray *features = [self.faceDetector featuresInImage:ciImage 
                                                   options:imageOptions];
	
    // get the clean aperture
    // the clean aperture is a rectangle that defines the portion of the encoded pixel dimensions
    // that represents image data valid for display.
	CMFormatDescriptionRef fdesc = CMSampleBufferGetFormatDescription(sampleBuffer);
	CGRect cleanAperture = CMVideoFormatDescriptionGetCleanAperture(fdesc, false /*originIsTopLeft == false*/);
	
	dispatch_async(dispatch_get_main_queue(), ^(void) {
		[self drawFaces:features
            forVideoBox:cleanAperture 
            orientation:curDeviceOrientation
                  image:ciImage];
	});
}

- (UIImage *)imageFromRect:(CGRect)rect image:(CIImage*)ciImage
{
    UIGraphicsBeginImageContext(rect.size);

    CGImageRef cropColourImage = [[CIContext contextWithOptions:nil] createCGImage:ciImage fromRect:rect];

    // Create bitmap image from original image data,
    // using rectangle to specify desired crop area
    UIImage *img = [UIImage imageWithCGImage:cropColourImage];
    CGImageRelease(cropColourImage);

//    [layer renderInContext:UIGraphicsGetCurrentContext()];
//    UIImage *outputImage = UIGraphicsGetImageFromCurrentImageContext();

    UIGraphicsEndImageContext();

    return [img convertToGrayscale];
//    return outputImage;
}

-(void) saveImage:(UIImage*)image
{
    if (self.mode == Detection)
        return;
    int maxCount =6;
    // Save the images in training mode so we can compare against these images
    // when trying to recognise faces
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *userDir1 = [baseDir stringByAppendingPathComponent:@"TrainingSetUser1"];
//    NSString *userDir2 = [baseDir stringByAppendingPathComponent:@"RecognitionSetUser2"];
    if (self.mode == Training)
    {
        [fm createDirectoryAtPath:userDir1
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];

        
        NSArray *dirContents = [fm contentsOfDirectoryAtPath:userDir1 error:nil];
        NSPredicate *fltr = [NSPredicate predicateWithFormat:@"self ENDSWITH '.jpg'"];
        NSArray *onlyJPGs = [dirContents filteredArrayUsingPredicate:fltr];
        // Create paths to output images
        NSString  *jpgPath = [userDir1 stringByAppendingPathComponent:[NSString stringWithFormat:@"%d_%d.jpg",numberOfSubjects,fileCount++]];

        NSLog(@"jpgPath:%@",jpgPath);
        // Write a UIImage to JPEG with minimum compression (best quality)
        // The value 'image' must be a UIImage object
        // The value '1.0' represents image compression quality as value from 0.0 to 1.0
        [UIImageJPEGRepresentation(image, 1.0) writeToFile:jpgPath atomically:YES];

        if ([onlyJPGs count] >=(maxCount +1)*numberOfSubjects-1)
        {
            // Let's get ready for recognition
            [((UIButton *)[self.view viewWithTag:10001]) setTitle:@"Train" forState:UIControlStateNormal];
            self.mode = Detection;
        }
    }
    else if (self.mode == Recognition)
    {
        [self.previewLayer.session stopRunning];
        // Let's get started with recognition
        self.mode = Detection;

        [fm createDirectoryAtPath:userDir1
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];


//        NSArray *dirContents = [fm contentsOfDirectoryAtPath:userDir1 error:nil];
//        NSPredicate *fltr = [NSPredicate predicateWithFormat:@"self ENDSWITH '.jpg'"];
//        NSArray *onlyJPGs = [dirContents filteredArrayUsingPredicate:fltr];
        // Create paths to output images
        NSString  *jpgPath = [userDir1 stringByAppendingPathComponent:@"MatchAgainst.jpg"];

        // Write a UIImage to JPEG with minimum compression (best quality)
        // The value 'image' must be a UIImage object
        // The value '1.0' represents image compression quality as value from 0.0 to 1.0
        [UIImageJPEGRepresentation(image, 1.0) writeToFile:jpgPath atomically:YES];

        [self tryMatchFaceWithTrainingUserSet:numberOfSubjects matchAgainst:jpgPath];

//        [self teardownAVCapture];

        // Remove the image directories
//            [fm removeItemAtPath:userDir1 error:nil];
//            [fm removeItemAtPath:userDir2 error:nil];
        [((UIButton *)[self.view viewWithTag:10002]) setTitle:@"Recognize" forState:UIControlStateNormal];
        [self doneLiveFeed:nil];

    }

}

-(void)tryMatchFaceWithTrainingUserSet:(int) numberOfSubjects matchAgainst:(NSString*)targetImagePath
{
    // Overridden?
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.navigationController setNavigationBarHidden:YES];
	// Do any additional setup after loading the view, typically from a nib.
    
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    
	[self setupAVCapture];
	self.borderImage = [UIImage imageNamed:@"border"];
	NSDictionary *detectorOptions = [[NSDictionary alloc] initWithObjectsAndKeys:CIDetectorAccuracyLow, CIDetectorAccuracy, nil];
	self.faceDetector = [CIDetector detectorOfType:CIDetectorTypeFace context:nil options:detectorOptions];
    [self addBackButton];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
    [self teardownAVCapture];
	self.faceDetector = nil;
	self.borderImage = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // We support only Portrait.
	return (interfaceOrientation == UIInterfaceOrientationPortrait);
}


@end
