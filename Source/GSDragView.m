/*
   GSDragView - Generic Drag and Drop code.

   Copyright (C) 2004 Free Software Foundation, Inc.

   Author: Fred Kiefer <fredkiefer@gmx.de>
   Date: May 2004

   Based on X11 specific code from:
   Created by: Wim Oudshoorn <woudshoo@xs4all.nl>
   Date: Nov 2001
   Written by:  Adam Fedor <fedor@gnu.org>
   Date: Nov 1998

   This file is part of the GNU Objective C User Interface Library.

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
   Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
   */

#include <Foundation/NSDebug.h>
#include <Foundation/NSThread.h>

#include <AppKit/NSApplication.h>
#include <AppKit/NSCell.h>
#include <AppKit/NSCursor.h>
#include <AppKit/NSImage.h>
#include <AppKit/NSPasteboard.h>
#include <AppKit/NSView.h>
#include <AppKit/NSWindow.h>

#include "GNUstepGUI/GSDisplayServer.h"
#include "GNUstepGUI/GSDragView.h"

/* Size of the dragged window */
#define	DWZ	48

#define SLIDE_TIME_STEP   .02   /* in seconds */
#define SLIDE_NR_OF_STEPS 20  

@interface GSRawWindow : NSWindow
@end

@interface NSCursor (BackendPrivate)
- (void *)_cid;
- (void) _setCid: (void *)val;
@end

@interface GSDragView (Private)
- (void) _setupWindowAt: (NSPoint) dragStart image: (NSImage*)anImage;
- (void) _clearupWindow;
- (BOOL) _updateOperationMask: (NSEvent*) theEvent;
- (void) _setCursor;
- (void) _sendLocalEvent: (GSAppKitSubtype)subtype
		  action: (NSDragOperation)action
	        position: (NSPoint)eventLocation
	       timestamp: (NSTimeInterval)time
	        toWindow: (NSWindow*)dWindow;
- (void) _sendExternalEvent: (GSAppKitSubtype)subtype
		     action: (NSDragOperation)action
		   position: (NSPoint)eventLocation
		  timestamp: (NSTimeInterval)time
		   toWindow: (int)dWindowNumber;
- (void) _handleDrag: (NSEvent*)theEvent;
- (void) _handleEventDuringDragging: (NSEvent *)theEvent;
- (void) _updateAndMoveImageToCorrectPosition;
- (void) _moveDraggedImageToNewPosition;
- (void) _slideDraggedImageTo: (NSPoint)screenPoint
                numberOfSteps: (int) steps
			delay: (float) delay
               waitAfterSlide: (BOOL) waitFlag;
- (NSWindow*) _windowAcceptingDnDunder: (NSPoint) mouseLocation
			     windowRef: (int*)mouseWindowRef;
@end

@implementation GSRawWindow

- (BOOL) canBecomeMainWindow
{
  return NO;
}

- (BOOL) canBecomeKeyWindow
{
  return NO;
}

- (void) _initDefaults
{
  [super _initDefaults];
  [self setReleasedWhenClosed: NO];
  [self setExcludedFromWindowsMenu: YES];
}

- (void) orderWindow: (NSWindowOrderingMode)place relativeTo: (int)otherWin
{
  [super orderWindow: place relativeTo: otherWin];
  [self setLevel: NSPopUpMenuWindowLevel];
}

@end


@implementation GSDragView

static	GSDragView *sharedDragView = nil;

+ (GSDragView*) sharedDragView
{
  if (sharedDragView == nil)
    {
      sharedDragView = [GSDragView new];
    }
  return sharedDragView;
}

+ (Class) windowClass
{
  return [GSRawWindow class];
}

- (id) init
{
  self = [super init];
  if (self != nil)
    {
      NSRect winRect = {{0, 0}, {DWZ, DWZ}};
      NSWindow *sharedDragWindow = [[isa windowClass] alloc];

      dragCell = [[NSCell alloc] initImageCell: nil];
      [dragCell setBordered: NO];
      
      [sharedDragWindow initWithContentRect: winRect
				  styleMask: NSBorderlessWindowMask
				    backing: NSBackingStoreNonretained
				      defer: NO];
      [sharedDragWindow setContentView: self];
      // Kept alive by the window
      RELEASE(self);
    }

  return self;
}

- (void) dealloc
{
  [super dealloc];
  RELEASE(cursors);
}

/* NSDraggingInfo protocol */
- (NSWindow*) draggingDestinationWindow
{
  return destWindow;
}

- (NSPoint) draggingLocation
{
  return dragPoint;
}

- (NSPasteboard*) draggingPasteboard
{
  return dragPasteboard;
}

- (int) draggingSequenceNumber
{
  return dragSequence;
}

- (id) draggingSource
{
  return dragSource;
}

- (unsigned int) draggingSourceOperationMask
{
  // Mix in possible modifiers
  return dragMask & operationMask;
}

- (NSImage*) draggedImage
{
  if (dragSource)
    return [dragCell image];
  else
    return nil;
}

- (NSPoint) draggedImageLocation
{
  NSPoint loc;

  if (dragSource)
    {
      loc = NSMakePoint(dragPoint.x - offset.x, dragPoint.y - offset.y);
    }
  else
    {
      loc = dragPoint;
    }

  return loc;
}


- (BOOL) isDragging
{
  return isDragging;
}

- (void) drawRect: (NSRect)rect
{
  [dragCell drawWithFrame: [self frame] inView: self];
}

/*
 * TODO:
 *  - use initialOffset
 */
- (void) dragImage: (NSImage*)anImage
		at: (NSPoint)screenLocation
	    offset: (NSSize)initialOffset
	     event: (NSEvent*)event
	pasteboard: (NSPasteboard*)pboard
	    source: (id)sourceObject
	 slideBack: (BOOL)slideFlag
{
  ASSIGN(dragPasteboard, pboard);
  ASSIGN(dragSource, sourceObject);
  dragSequence = [event timestamp];
  slideBack = slideFlag;

  // Unset the target window  
  targetWindowRef = 0;
  targetMask = NSDragOperationAll;
  destExternal = NO;

  NSDebugLLog(@"NSDragging", @"Start drag with %@", [pboard types]);
  [self _setupWindowAt: screenLocation image: anImage];
  isDragging = YES;
  [self _handleDrag: event];
  isDragging = NO;
  DESTROY(dragSource);
  DESTROY(dragPasteboard);
}

- (void) slideDraggedImageTo:  (NSPoint) point
{
  [self _slideDraggedImageTo: point 
	       numberOfSteps: SLIDE_NR_OF_STEPS 
	               delay: SLIDE_TIME_STEP
	      waitAfterSlide: YES];
}

/* 
   Called by NSWindow. Sends drag events to external sources
 */
- (void) postDragEvent: (NSEvent *)theEvent
{
  if ([theEvent subtype] == GSAppKitDraggingStatus)
    {
      NSDragOperation action = [theEvent data2];

      if (destExternal)
	{

	}
      else
        {	 
	  if (action != targetMask)
	    {
	      targetMask = action;
	      [self _setCursor];
	    }
	}
    }
}

@end

@implementation GSDragView (Private)

/*
  Method to initialize the dragview before it is put on the screen.
  It only initializes the instance variables that have to do with
  moving the image over the screen and variables that are used
  to keep track where we are.

  So it is typically used just before the dragview is actually displayed.

  Post conditions:
  - dragCell is initialized with the image to drag.
  - all instance variables pertaining to moving the window are initialized
 */
- (void) _setupWindowAt: (NSPoint) dragStart image: (NSImage*)anImage
{
  NSSize imageSize;

  if (anImage == nil)
    {
      anImage = [NSImage imageNamed: @"common_Close"];
    }

  [dragCell setImage: anImage];
  imageSize = [anImage size];
  offset = NSMakePoint (imageSize.width / 2.0, imageSize.height / 2.0);
  
  [_window setFrame: NSMakeRect (dragStart.x - offset.x, 
                                 dragStart.y - offset.y,
                                 imageSize.width, imageSize.height)
           display: NO];

  /* setup the coordinates, used for moving the view around */
  dragPosition = dragStart;
  newPosition = dragStart;

  // Only display the image
  [GSServerForWindow(_window) restrictWindow: [_window windowNumber]
                                     toImage: [dragCell image]];

  [_window orderFront: nil];
}

- (void) _clearupWindow
{
  [_window orderOut: nil];
}

/*
  updates the operationMask by examining modifier keys
  pressed during -theEvent-.

  If the current value of operationMask == NSDragOperationIgnoresModifiers
  it will return immediately without updating the operationMask
  
  This method will return YES if the operationMask
  is changed, NO if it is still the same.
*/
- (BOOL) _updateOperationMask: (NSEvent*) theEvent
{
  unsigned int mod = [theEvent modifierFlags];
  unsigned int oldOperationMask = operationMask;

  if (operationMask == NSDragOperationIgnoresModifiers)
    {
      return NO;
    }
  
  if (mod & NSControlKeyMask)
    {
      operationMask = NSDragOperationLink;
    }
  else if (mod & NSAlternateKeyMask)
    {
      operationMask = NSDragOperationCopy;
    }
  else if (mod & NSCommandKeyMask)
    {
      operationMask = NSDragOperationGeneric;
    }
  else
    {
      operationMask = NSDragOperationAll;
    }

  return (operationMask != oldOperationMask);
}

/**
  _setCursor examines the state of the dragging and update
  the cursor accordingly.  It will not save the current cursor,
  if you want to keep the original you have to save it yourself.

  The code recogines 4 cursors:

  - NONE - when the source does not allow dragging
  - COPY - when the current operation is ONLY Copy
  - LINK - when the current operation is ONLY Link
  - GENERIC - all other cases

  And two colors

  - GREEN - when the target accepts the drop
  - BLACK - when the target does not accept the drop

  Note that the code to figure out which of the 4 cursor to use
  depends on the fact that

  {NSDragOperationNone, NSDragOperationCopy, NSDragOperationLink} = {0, 1, 2}
*/
- (void) _setCursor
{
  NSCursor *newCursor;
  NSString *name;
  NSString *iname;
  int       mask;

  mask = dragMask & operationMask;

  if (targetWindowRef != 0)
    mask &= targetMask;

  NSDebugLLog (@"NSDragging",
               @"drag, operation, target mask = (%x, %x, %x), dnd aware = %d\n",
               dragMask, operationMask, targetMask,
               (targetWindowRef != 0));
  
  if (cursors == nil)
    cursors = RETAIN([NSMutableDictionary dictionary]);
  
  name = nil;
  newCursor = nil;
  switch (mask)
    {
    case NSDragOperationNone:
      name = @"NoCursor";
      iname = @"common_noCursor";
      break;
    case NSDragOperationCopy:
      name = @"CopyCursor";
      iname = @"common_copyCursor";
      break;
    case NSDragOperationLink:
      name = @"LinkCursor";
      iname = @"common_linkCursor";
      break;
    case NSDragOperationGeneric:
      break;
    default:
      // FIXME: Should not happen, add warning?
      break;
    }

  if (name != nil)
    {
      newCursor = [cursors objectForKey: name];
      if (newCursor == nil)
	{
	  NSImage *image = [NSImage imageNamed: iname];
	  newCursor = [[NSCursor alloc] initWithImage: image];
	  [cursors setObject: newCursor forKey: name];
	  RELEASE(newCursor);
	}
    }
  if (newCursor == nil)
    {
      name = @"ArrowCursor";
      newCursor = [cursors objectForKey: name];
      if (newCursor == nil)
	{
	  /* Make our own arrow cursor, since we want to color it */
	  void *c;
	  
	  newCursor = [[NSCursor alloc] initWithImage: nil];
	  [GSCurrentServer() standardcursor: GSArrowCursor : &c];
	  [newCursor _setCid: c];
	  [cursors setObject: newCursor forKey: name];
	  RELEASE(newCursor);
	}
    }
  
  [newCursor set];

  if ((targetWindowRef != 0) && mask != NSDragOperationNone)
    {
      [GSCurrentServer() setcursorcolor: [NSColor greenColor] 
		      : [NSColor blackColor] 
		      : [newCursor _cid]];
    }
  else
    {
      [GSCurrentServer() setcursorcolor: [NSColor blackColor] 
		      : [NSColor whiteColor] 
		      : [newCursor _cid]];
    }
}

- (void) _sendLocalEvent: (GSAppKitSubtype)subtype
		  action: (NSDragOperation)action
	        position: (NSPoint)eventLocation
	       timestamp: (NSTimeInterval)time
	        toWindow: (NSWindow*)dWindow
{
  NSEvent *e;
  NSGraphicsContext *context = GSCurrentContext();
  // FIXME: Should store this once
  int dragWindowRef = (int)[GSServerForWindow(_window) windowDevice: [_window windowNumber]];

  eventLocation = [dWindow convertScreenToBase: eventLocation];
  e = [NSEvent otherEventWithType: NSAppKitDefined
	                 location: eventLocation
	            modifierFlags: 0
	                timestamp: time
	             windowNumber: [dWindow windowNumber]
	                  context: context
	                  subtype: subtype
	                    data1: dragWindowRef
	                    data2: action];
  [dWindow sendEvent: e];
}

- (void) _sendExternalEvent: (GSAppKitSubtype)subtype
		     action: (NSDragOperation)action
		   position: (NSPoint)eventLocation
		  timestamp: (NSTimeInterval)time
		   toWindow: (int)dWindowNumber
{
}

/*
  The dragging support works by hijacking the NSApp event loop.

  - this function loops until the dragging operation is finished
    and consumes all NSEvents during the drag operation.

  - It sets up periodic events.  The drawing and communication
    with DraggingSource and DraggingTarget is handled in the
    periodic event code.  The use of periodic events is purely
    a performance improvement.  If no periodic events are used
    the system can not process them all on time.
    At least on a 333Mhz laptop, using fairly simple
    DraggingTarget code.

  PROBLEMS:

  - No autoreleasePools are created.  So long drag operations can consume
    memory

  - It seems that sometimes a periodic event get lost.
*/
- (void) _handleDrag: (NSEvent*)theEvent
{
  // Caching some often used values. These values do not
  // change in this method.
  // Use eWindow for coordination transformation
  NSWindow	*eWindow = [theEvent window];
  NSDate	*theDistantFuture = [NSDate distantFuture];
  unsigned int	eventMask = NSLeftMouseDownMask | NSLeftMouseUpMask
    | NSLeftMouseDraggedMask | NSMouseMovedMask
    | NSPeriodicMask | NSAppKitDefinedMask | NSFlagsChangedMask;
  NSPoint       startPoint;
  // Storing values, to restore after we have finished.
  NSCursor      *cursorBeforeDrag = [NSCursor currentCursor];
  BOOL deposited;

  startPoint = [eWindow convertBaseToScreen: [theEvent locationInWindow]];
  NSDebugLLog(@"NSDragging", @"Drag window origin %d %d\n", startPoint.x, startPoint.y);

  // Notify the source that dragging has started
  if ([dragSource respondsToSelector:
      @selector(draggedImage:beganAt:)])
    {
      [dragSource draggedImage: [self draggedImage]
		  beganAt: startPoint];
    }

  // --- Setup up the masks for the drag operation ---------------------
  if ([dragSource respondsToSelector:
    @selector(ignoreModifierKeysWhileDragging)]
    && [dragSource ignoreModifierKeysWhileDragging])
    {
      operationMask = NSDragOperationIgnoresModifiers;
    }
  else
    {
      operationMask = 0;
      [self _updateOperationMask: theEvent];
    }

  dragMask = [dragSource draggingSourceOperationMaskForLocal: !destExternal];
  
  // --- Setup the event loop ------------------------------------------
  [self _updateAndMoveImageToCorrectPosition];
  [NSEvent startPeriodicEventsAfterDelay: 0.02 withPeriod: 0.03];

  // --- Loop that handles all events during drag operation -----------
  while ([theEvent type] != NSLeftMouseUp)
    {
      [self _handleEventDuringDragging: theEvent];

      theEvent = [NSApp nextEventMatchingMask: eventMask
				    untilDate: theDistantFuture
				       inMode: NSEventTrackingRunLoopMode
				      dequeue: YES];
    }

  // --- Event loop for drag operation stopped ------------------------
  [NSEvent stopPeriodicEvents];
  [self _updateAndMoveImageToCorrectPosition];

  NSDebugLLog(@"NSDragging", @"dnd ending %d\n", targetWindowRef);

  // --- Deposit the drop ----------------------------------------------
  if ((targetWindowRef != 0)
    && ((targetMask & dragMask & operationMask) != NSDragOperationNone))
    {
      // FIXME:
      // We remove the dragged image from the screen before 
      // sending the dnd drop event to the destination.
      // This code should actually be rewritten, because
      // the depositing of the drop consist of three steps
      //  - prepareForDragOperation
      //  - performDragOperation
      //  - concludeDragOperation.
      // The dragged image should be removed from the screen
      // between the prepare and the perform operation.
      // The three steps are now executed in the NSWindow class
      // and the NSWindow class does not have access to
      // the image.
      [self _clearupWindow];
      [cursorBeforeDrag set];
      NSDebugLLog(@"NSDragging", @"sending dnd drop\n");
      if (!destExternal)
	{
	  [self _sendLocalEvent: GSAppKitDraggingDrop
			 action: 0
		       position: NSZeroPoint
		      timestamp: [theEvent timestamp]
		       toWindow: destWindow];
	}
      else
	{
	  [self _sendExternalEvent: GSAppKitDraggingDrop
		            action: 0
		          position: NSZeroPoint
		         timestamp: [theEvent timestamp]
		          toWindow: targetWindowRef];
	}
      deposited = YES;
    }
  else
    {
      if (slideBack)
        {
          [self slideDraggedImageTo: startPoint];
        }
      [self _clearupWindow];
      [cursorBeforeDrag set];
      deposited = NO;
    }

  if ([dragSource respondsToSelector:
		      @selector(draggedImage:endedAt:deposited:)])
    {
      NSPoint point;
          
      point = [theEvent locationInWindow];
      point = [[theEvent window] convertBaseToScreen: point];
      [dragSource draggedImage: [self draggedImage]
		       endedAt: point
		     deposited: deposited];
    }
}

/*
 * Handle the events for the event loop during drag and drop
 */
- (void) _handleEventDuringDragging: (NSEvent *)theEvent
{
  switch ([theEvent type])
    {
    case  NSAppKitDefined:
      {
        GSAppKitSubtype	sub = [theEvent subtype];
        
        switch (sub)
        {
        case GSAppKitWindowMoved:
          /*
           * Keep window up-to-date with its current position.
           */
          [NSApp sendEvent: theEvent];
          break;
          
        case GSAppKitDraggingStatus:
          NSDebugLLog(@"NSDragging", @"got GSAppKitDraggingStatus\n");
          if ((int)[theEvent data1] == targetWindowRef)
            {
              unsigned int newTargetMask = [theEvent data2];

              if (newTargetMask != targetMask)
                {
                  targetMask = newTargetMask;
                  [self _setCursor];
                }
            }
          break;
          
        case GSAppKitDraggingFinished:
          NSLog(@"Internal: got GSAppKitDraggingFinished out of seq");
          break;
          
        case GSAppKitWindowFocusIn:
	case GSAppKitWindowFocusOut:
	case GSAppKitWindowLeave:
	case GSAppKitWindowEnter:
          break;
          
        default:
          NSLog(@"Internal: dropped NSAppKitDefined (%d) event", sub);
          break;
        }
      }
      break;
      
    case NSMouseMoved:
    case NSLeftMouseDragged:
    case NSLeftMouseDown:
    case NSLeftMouseUp:
      newPosition = [[theEvent window] convertBaseToScreen:
	[theEvent locationInWindow]];
      break;
    case NSFlagsChanged:
      if ([self _updateOperationMask: theEvent])
        {
	  // If flags change, send update to allow
	  // destination to take note.
	  if (destWindow)
            {
              [self _sendLocalEvent: GSAppKitDraggingUpdate
		    action: dragMask & operationMask
		    position: NSMakePoint(newPosition.x + offset.x, newPosition.y + offset.y)
		    timestamp: [theEvent timestamp]
		    toWindow: destWindow];
	    }
	  else
	    {
              [self _sendExternalEvent: GSAppKitDraggingUpdate
		    action: dragMask & operationMask
		    position: NSMakePoint(newPosition.x + offset.x, newPosition.y + offset.y)
		    timestamp: [theEvent timestamp]
		    toWindow: targetWindowRef];
	    }
          [self _setCursor];
        }
      break;
    case NSPeriodic:
      newPosition = [NSEvent mouseLocation];
      if (newPosition.x != dragPosition.x || newPosition.y != dragPosition.y) 
        {
          [self _updateAndMoveImageToCorrectPosition];
        }
      break;
    default:
      NSLog(@"Internal: dropped event (%d) during dragging", [theEvent type]);
    }
}
  
/*
 * This method will move the drag image and update all associated data
 */
- (void) _updateAndMoveImageToCorrectPosition
{
  //--- Store old values -----------------------------------------------------
  NSWindow *oldDestWindow = destWindow;
  BOOL oldDestExternal = destExternal;
  int mouseWindowRef; 
  BOOL changeCursor = NO;
  NSPoint mouseLocation = NSMakePoint(dragPosition.x + offset.x, dragPosition.y + offset.y);
 
  //--- Move drag image to the new position -----------------------------------
  [self _moveDraggedImageToNewPosition];
  
  //--- Determine target window ---------------------------------------------
 destWindow = [self _windowAcceptingDnDunder: mouseLocation
                                   windowRef: &mouseWindowRef];

  // If we have are not hovering above a window that we own
  // we are dragging to an external application.
  destExternal = (mouseWindowRef != 0) && (destWindow == nil);
            
  if (destWindow != nil)
    {
      dragPoint = [destWindow convertScreenToBase: dragPosition];
    }
            
  NSDebugLLog(@"NSDragging", @"mouse window %d\n", mouseWindowRef);
            
  //--- send exit message if necessary -------------------------------------
  if ((mouseWindowRef != targetWindowRef) && targetWindowRef)
    {
      /* If we change windows and the old window is dnd aware, we send an
         dnd exit */
      NSDebugLLog(@"NSDragging", @"sending dnd exit\n");
                
      if (oldDestWindow != nil)   
        {
          [self _sendLocalEvent: GSAppKitDraggingExit
			 action: dragMask & operationMask
		       position: NSZeroPoint
                      timestamp: dragSequence
		       toWindow: oldDestWindow];
        }  
      else
        {  
          [self _sendExternalEvent: GSAppKitDraggingExit
		            action: dragMask & operationMask
		          position: NSZeroPoint
		         timestamp: dragSequence
		          toWindow: targetWindowRef];
        }
    }

  //  Reset drag mask when we switch from external to internal or back
  if (oldDestExternal != destExternal)
    {
      unsigned int newMask;

      newMask = [dragSource draggingSourceOperationMaskForLocal: destExternal];
      if (newMask != dragMask)
        {
          dragMask = newMask;
          changeCursor = YES;
        }
    }

  if (mouseWindowRef == targetWindowRef && targetWindowRef)  
    { 
      // same window, sending update
      NSDebugLLog(@"NSDragging", @"sending dnd pos\n");

      if (destWindow != nil)
        {
          [self _sendLocalEvent: GSAppKitDraggingUpdate
			 action: dragMask & operationMask
		       position: mouseLocation
		      timestamp: dragSequence
		       toWindow: destWindow];
        }
      else 
        {
	  [self _sendExternalEvent: GSAppKitDraggingUpdate 
		            action: dragMask & operationMask
		          position: mouseLocation
		         timestamp: dragSequence
		          toWindow: targetWindowRef];
        }
    }
  else if (mouseWindowRef != 0)
    {
      // FIXME: We might force the cursor update here, if the
      // target wants to change the cursor.
      NSDebugLLog(@"NSDragging", @"sending dnd enter/pos\n");
      
      if (destWindow != nil)
        {
          [self _sendLocalEvent: GSAppKitDraggingEnter
                action: dragMask
                position: mouseLocation
                timestamp: dragSequence
                toWindow: destWindow];
        }
      else
        {
          [self _sendExternalEvent: GSAppKitDraggingEnter
                            action: dragMask
                          position: mouseLocation
                         timestamp: dragSequence
                          toWindow: mouseWindowRef];
        }
    }

  if (targetWindowRef != mouseWindowRef)
    {
      targetWindowRef = mouseWindowRef;
      changeCursor = YES;
    }
  
  if (changeCursor)
    {
      [self _setCursor];
    }
}

/*
 * Move the dragged image immediately to the position indicated by
 * the instance variable newPosition.
 *
 * In doing so it will update the dragPosition instance variables.
 */
- (void) _moveDraggedImageToNewPosition
{
  dragPosition = newPosition;
  [GSServerForWindow(_window) movewindow: NSMakePoint(newPosition.x - offset.x, 
						      newPosition.y - offset.y) 
		                        : [_window windowNumber]];
}


- (void) _slideDraggedImageTo: (NSPoint)screenPoint
                numberOfSteps: (int) steps
			delay: (float) delay
               waitAfterSlide: (BOOL) waitFlag
{
  // --- If we do not need multiple redrawing, just move the image immediately
  //     to its desired spot.
  if (steps < 2)
    {
      newPosition = screenPoint;
      [self _moveDraggedImageToNewPosition];
    }
  else
    {
      [NSEvent startPeriodicEventsAfterDelay: delay withPeriod: delay];

      // Use the event loop to redraw the image repeatedly.
      // Using the event loop to allow the application to process
      // expose events.  
      while (steps)
        {
          NSEvent *theEvent = [NSApp nextEventMatchingMask: NSPeriodicMask
                                     untilDate: [NSDate distantFuture]
                                     inMode: NSEventTrackingRunLoopMode
                                     dequeue: YES];
          
          if ([theEvent type] != NSPeriodic)
            {
              NSDebugLLog (@"NSDragging", 
			   @"Unexpected event type: %d during slide",
                           [theEvent type]);
            }
          newPosition.x = (screenPoint.x + ((float) steps - 1.0) 
			   * dragPosition.x) / ((float) steps);
          newPosition.y = (screenPoint.y + ((float) steps - 1.0) 
			   * dragPosition.y) / ((float) steps);

          [self _moveDraggedImageToNewPosition];
          steps--;
        }
      [NSEvent stopPeriodicEvents];
    }

  if (waitFlag)
    {
      [NSThread sleepUntilDate: 
	[NSDate dateWithTimeIntervalSinceNow: delay * 2.0]];
    }
}

/*
  Return the window that lies below the cursor and accepts drag and drop.
  In mouseWindowRef the OS reference for this window is returned, this is even 
  set, if there is a native window, but no GNUstep window at this location.
 */
- (NSWindow*) _windowAcceptingDnDunder: (NSPoint)mouseLocation
			     windowRef: (int*)mouseWindowRef
{
  int win;

  *mouseWindowRef = 0;
  win = [GSServerForWindow(_window) findWindowAt: mouseLocation
			  windowRef: mouseWindowRef
			  excluding: [_window windowNumber]];

  return GSWindowWithNumber(win);
}

@end
