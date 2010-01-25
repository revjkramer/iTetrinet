//
//  iTetField.h
//  iTetrinet
//
//  Created by Alex Heinz on 6/5/09.
//

#import <Cocoa/Cocoa.h>

#define ITET_FIELD_WIDTH	12
#define ITET_FIELD_HEIGHT	22

typedef enum
{
	obstructNone =	0,
	obstructVert =	1,
	obstructHoriz =	2
} iTetObstructionState;

@class iTetBlock;

@interface iTetField: NSObject <NSCopying>
{
	char contents[ITET_FIELD_HEIGHT][ITET_FIELD_WIDTH];
	
	NSString* lastPartialUpdate;
}

// Initializer for an empty field
+ (id)field;

// Initializers for a field with a starting stack height
+ (id)fieldWithStackHeight:(NSUInteger)stackHeight;
- (id)initWithStackHeight:(NSUInteger)stackHeight;

// Initializers for a random field
+ (id)fieldWithRandomContents;
- (id)initWithRandomContents;

// Copy initializer
- (id)initWithContents:(char[ITET_FIELD_HEIGHT][ITET_FIELD_WIDTH])fieldContents;

// Checks whether a block is in a valid position on the field
- (iTetObstructionState)blockObstructed:(iTetBlock*)block;

// Checks whether the specified cell is valid (i.e., on the field) and empty
- (iTetObstructionState)cellObstructedAtRow:(int)row
						 column:(int)col;

// Add the cells of the specified block to the field's contents
- (void)solidifyBlock:(iTetBlock*)block;

// Check for and clear completed lines on the board; returns the number of lines cleared
- (NSUInteger)clearLines;

// Returns the contents of the specified cell of the field
- (char)cellAtRow:(NSUInteger)row
	     column:(NSUInteger)column;

// The current fieldstring that describes the state of the field
@property (readonly) NSString* fieldstring;

// The fieldstring for last partial update
@property (readwrite, retain) NSString* lastPartialUpdate;

@end
