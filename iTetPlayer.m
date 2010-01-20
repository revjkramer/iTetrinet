//
//  iTetPlayer.m
//  iTetrinet
//
//  Created by Alex Heinz on 6/17/09.
//

#import "iTetPlayer.h"

@implementation iTetPlayer

+ (id)playerWithNickname:(NSString*)nick
			number:(int)number
		    teamName:(NSString*)team
{
	return [[[self alloc] initWithNickname:nick
						  number:number
						teamName:team] autorelease];
}
- (id)initWithNickname:(NSString*)nick
		    number:(int)number
		  teamName:(NSString*)team
{
	nickname = [nick copy];
	playerNumber = number;
	teamName = [team copy];
	
	field = [[iTetField alloc] initWithRandomContents];
	
	return self;
}

+ (id)playerWithNickname:(NSString*)nick
			number:(int)number
{
	return [[[self alloc] initWithNickname:nick
						  number:number] autorelease];
}
- (id)initWithNickname:(NSString*)nick
		    number:(int)number
{
	return [self initWithNickname:nick
				     number:number
				   teamName:@""];
}

+ (id)playerWithNumber:(int)number
{
	return [[[self alloc] initWithNumber:number] autorelease];
}
- (id)initWithNumber:(int)number
{
	return [self initWithNickname:@"Unnamed Player"
				     number:number];
}

- (void)dealloc
{
	[nickname release];
	[teamName release];
	[field release];
	
	[super dealloc];
}

#pragma mark -
#pragma mark Accessors

@synthesize nickname;
@synthesize playerNumber;
@synthesize teamName;
@synthesize field;
@synthesize level;

@end
