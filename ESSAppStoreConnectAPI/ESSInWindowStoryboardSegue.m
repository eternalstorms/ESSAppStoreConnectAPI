//
//  ESSInWindowStoryboardSegue.m
//  PromoCodes
//
//  Created by Matthias Gansrigler on 13.02.2019.
//  Copyright © 2019 Eternal Storms Software. All rights reserved.
//

#import "ESSInWindowStoryboardSegue.h"

@implementation ESSInWindowStoryboardSegue

- (void)perform
{
	NSWindow *containerWindow = nil;
	if ([self.sourceController isKindOfClass:[NSViewController class]])
	{
		containerWindow = ((NSViewController *)self.sourceController).view.window;
	} else if ([self.sourceController isKindOfClass:[NSWindowController class]])
	{
		containerWindow = ((NSWindowController *)self.sourceController).window;
	}
	
	[containerWindow.contentViewController resignFirstResponder];
	containerWindow.contentView = nil;
	containerWindow.contentViewController = nil;
	
	NSRect newFrame = NSMakeRect(containerWindow.frame.origin.x,
								 containerWindow.frame.origin.y - (((NSViewController *)self.destinationController).view.frame.size.height-containerWindow.frame.size.height),
								 ((NSViewController *)self.destinationController).view.frame.size.width,
								 ((NSViewController *)self.destinationController).view.frame.size.height);
	CGFloat duration = [containerWindow animationResizeTime:newFrame];
	[containerWindow setFrame:newFrame display:YES animate:YES];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		containerWindow.contentViewController = self.destinationController;
		containerWindow.contentView = ((NSViewController *)self.destinationController).view;
		[containerWindow makeFirstResponder:containerWindow.contentView];
	});
}

@end
