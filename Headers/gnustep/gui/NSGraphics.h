/*
   NSGraphics.h

   Copyright (C) 1996 Free Software Foundation, Inc.

   Author: Ovidiu Predescu <ovidiu@net-community.com>
   Date: February 1997
   
   This file is part of the GNUstep GUI Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.
*/
#ifndef __NSGraphics_h__
#define __NSGraphics_h__

#include <Foundation/NSObject.h>
#include <Foundation/NSGeometry.h>

@class NSString;
@class NSColor;
@class NSGraphicsContext;

/*
 * Colorspace Names 
 */
extern NSString *NSCalibratedWhiteColorSpace; 
extern NSString *NSCalibratedBlackColorSpace; 
extern NSString *NSCalibratedRGBColorSpace;
extern NSString *NSDeviceWhiteColorSpace;
extern NSString *NSDeviceBlackColorSpace;
extern NSString *NSDeviceRGBColorSpace;
extern NSString *NSDeviceCMYKColorSpace;
extern NSString *NSNamedColorSpace;
extern NSString *NSCustomColorSpace;

typedef int NSWindowDepth;

/*
 * Color function externs
 */
extern const NSWindowDepth _GSGrayBitValue;
extern const NSWindowDepth _GSRGBBitValue;
extern const NSWindowDepth _GSCMYKBitValue;
extern const NSWindowDepth _GSCustomBitValue;
extern const NSWindowDepth _GSNamedBitValue;
extern const NSWindowDepth *_GSWindowDepths[7];
extern const NSWindowDepth NSDefaultDepth;
extern const NSWindowDepth NSTwoBitGrayDepth;
extern const NSWindowDepth NSEightBitGrayDepth;
extern const NSWindowDepth NSEightBitRGBDepth;
extern const NSWindowDepth NSTwelveBitRGBDepth;
extern const NSWindowDepth GSSixteenBitRGBDepth;
extern const NSWindowDepth NSTwentyFourBitRGBDepth;

/*
 * Gray Values 
 */
extern const float NSBlack;
extern const float NSDarkGray;
extern const float NSWhite;
extern const float NSLightGray;
extern const float NSGray;

/*
 * Device Dictionary Keys 
 */
extern NSString *NSDeviceResolution;
extern NSString *NSDeviceColorSpaceName;
extern NSString *NSDeviceBitsPerSample;
extern NSString *NSDeviceIsScreen;
extern NSString *NSDeviceIsPrinter;
extern NSString *NSDeviceSize;

/*
 * Rectangle Drawing Functions
 */
void NSEraseRect(NSRect aRect);
void NSHighlightRect(NSRect aRect);
void NSRectClip(NSRect aRect);
void NSRectClipList(const NSRect *rects, int count);
void NSRectFill(NSRect aRect);
void NSRectFillList(const NSRect *rects, int count);
void NSRectFillListWithGrays(const NSRect *rects, 
			     const float *grays, int count);

/*
 * Draw a Bordered Rectangle
 */
void NSDrawButton(const NSRect aRect, const NSRect clipRect);
void NSDrawGrayBezel(const NSRect aRect, const NSRect clipRect);
void NSDrawGroove(const NSRect aRect, const NSRect clipRect);
NSRect NSDrawTiledRects(NSRect aRect, const NSRect clipRect, 
			const NSRectEdge *sides, const float *grays, 
			int count);
void NSDrawWhiteBezel(const NSRect aRect, const NSRect clipRect);
void NSDottedFrameRect(const NSRect aRect);
void NSFrameRect(const NSRect aRect);
void NSFrameRectWithWidth(const NSRect aRect, float frameWidth);

/*
 * Get Information About Color Space and Window Depth
 */
const NSWindowDepth *NSAvailableWindowDepths(void);
NSWindowDepth NSBestDepth(NSString *colorSpace, 
			  int bitsPerSample, int bitsPerPixel, 
			  BOOL planar, BOOL *exactMatch);
int NSBitsPerPixelFromDepth(NSWindowDepth depth);
int NSBitsPerSampleFromDepth(NSWindowDepth depth);
NSString *NSColorSpaceFromDepth(NSWindowDepth depth);
int NSNumberOfColorComponents(NSString *colorSpaceName);
BOOL NSPlanarFromDepth(NSWindowDepth depth);

/*
 * Read the Color at a Screen Position
 */
NSColor *NSReadPixel(NSPoint location);

/*
 * Copy an image
 */
void NSCopyBitmapFromGState(int srcGstate, NSRect srcRect, NSRect destRect);
void NSCopyBits(int srcGstate, NSRect srcRect, NSPoint destPoint);

/*
 * Render Bitmap Images
 */
void NSDrawBitmap(NSRect rect,
                  int pixelsWide,
                  int pixelsHigh,
                  int bitsPerSample,
                  int samplesPerPixel,
                  int bitsPerPixel,
                  int bytesPerRow, 
                  BOOL isPlanar,
                  BOOL hasAlpha, 
                  NSString *colorSpaceName, 
                  const unsigned char *const data[5]);

/*
 * Play the System Beep
 */
void NSBeep(void);

/*
 * Functions for getting information about windows.
 */
void NSCountWindows(int *count);
void NSWindowList(int size, int list[]);

#ifndef	NO_GNUSTEP
@class	NSArray;
@class	NSWindow;

NSArray* GSAllWindows();
NSWindow* GSWindowWithNumber(int num);

#endif

#endif /* __NSGraphics_h__ */
