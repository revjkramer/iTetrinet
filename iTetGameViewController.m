//
//  iTetGameViewController.m
//  iTetrinet
//
//  Created by Alex Heinz on 10/7/09.
//  Copyright (c) 2009-2010 Alex Heinz (xale@acm.jhu.edu)
//  This is free software, presented under the MIT License
//  See the included license.txt for more information
//

#import "iTetGameViewController.h"

#import "iTetWindowController.h"
#import "iTetPlayersController.h"
#import "iTetUserDefaults.h"

#import "iTetNetworkController.h"
#import "iTetMessage.h"

#import "iTetGameRules.h"
#import "iTetLocalPlayer.h"
#import "iTetServerPlayer.h"
#import "iTetServerInfo.h"
#import "iTetField.h"
#import "iTetBlock.h"
#import "iTetSequencedBlockGenerator.h"

#import "iTetLocalFieldView.h"
#import "iTetNextBlockView.h"
#import "iTetSpecialsView.h"
#import "IPSScalableLevelIndicator.h"

#import "iTetKeyActions.h"
#import "iTetKeyConfiguration.h"

#import "iTetTextAttributes.h"

#import "iTetCommonLocalizations.h"

#import "NSDictionary+AdditionalTypes.h"

#define LOCALPLAYER	[playersController localPlayer]

NSTimeInterval blockFallDelayForLevel(NSInteger level);

@interface iTetGameViewController (Private)

- (void)moveCurrentBlockDown;
- (void)solidifyBlock:(iTetBlock*)block;
- (void)checkForLinesCleared:(iTetField*)field;
- (void)moveNextBlockToField;
- (void)useSpecial:(iTetSpecialType)special
		  onTarget:(iTetPlayer*)target
		fromSender:(iTetPlayer*)sender;
- (void)playerLost;

- (void)sendFieldUpdate;
- (void)sendCurrentLevel;
- (void)sendSpecial:(iTetSpecialType)special
		   toPlayer:(iTetPlayer*)target;
- (void)sendLines:(NSInteger)lines;

- (void)appendEventDescription:(NSAttributedString*)description;
- (void)clearActions;

- (void)startNextBlockTimer;
- (void)startBlockFallTimer;
- (void)pauseBlockTimer;
- (void)resumeBlockTimer;

- (BOOL)offlineGame;

- (void)setCurrentKeyConfiguration:(iTetKeyConfiguration*)config;

@end

@implementation iTetGameViewController

+ (void)initialize
{
	if (self == [iTetGameViewController class])
	{
		[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObject:[iTetGameRules defaultOfflineGameRules]
																							forKey:iTetOfflineGameRulesPrefKey]];
		
		// Seed random number generator
		srandom(time(NULL));
	}
}

- (id)init
{
	gameplayState = gameNotPlaying;
	
	// Load the default key bindings
	currentKeyConfiguration = [[iTetKeyConfiguration currentKeyConfiguration] retain];
	
	// Register for notifications of changes to the key bindings
	[[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
															  forKeyPath:[@"values." stringByAppendingString:iTetCurrentKeyConfigNumberPrefKey]
																 options:0
																 context:NULL];
	
	return self;
}

- (void)awakeFromNib
{
	// Bind the game views to the app controller, and all views to the current theme
	// Local field view (field and falling block)
	[localFieldView bind:@"field"
				toObject:playersController
			 withKeyPath:@"localPlayer.field"
				 options:nil];
	[localFieldView bind:@"block"
				toObject:playersController
			 withKeyPath:@"localPlayer.currentBlock"
				 options:nil];
	
	// Next block view
	[nextBlockView bind:@"block"
			   toObject:playersController
			withKeyPath:@"localPlayer.nextBlock"
				options:nil];
	
	// Specials queue view
	[specialsView bind:@"specials"
			  toObject:playersController
		   withKeyPath:@"localPlayer.specialsQueue"
			   options:nil];
	[specialsView bind:@"capacity"
			  toObject:self
		   withKeyPath:@"currentGameRules.iTetSpecialCapacity"
			   options:[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:0]
												   forKey:NSNullPlaceholderBindingOption]];
	
	// Level progress indicator
	[levelProgressIndicator bind:@"maxValue"
						toObject:self
					 withKeyPath:@"currentGameRules.iTetLinesPerLevel"
						 options:[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:1]
															 forKey:NSNullPlaceholderBindingOption]];
	[levelProgressIndicator bind:@"value"
						toObject:playersController
					 withKeyPath:@"localPlayer.linesSinceLastLevel"
						 options:[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:0]
															 forKey:NSNullPlaceholderBindingOption]];
	
	// Specials progress indicator
	[specialsProgressIndicator bind:@"hidden"
						   toObject:self
						withKeyPath:@"currentGameRules.iTetSpecialsEnabled"
							options:[NSDictionary dictionaryWithObject:NSNegateBooleanTransformerName
																forKey:NSValueTransformerNameBindingOption]];
	[specialsProgressIndicator bind:@"maxValue"
						   toObject:self
						withKeyPath:@"currentGameRules.iTetLinesPerSpecial"
							options:[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:1]
																forKey:NSNullPlaceholderBindingOption]];
	[specialsProgressIndicator bind:@"value"
						   toObject:playersController
						withKeyPath:@"localPlayer.linesSinceLastSpecials"
							options:[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:0]
																forKey:NSNullPlaceholderBindingOption]];
	
	// Remote field views
	[remoteFieldView1 bind:@"field"
				  toObject:playersController
			   withKeyPath:@"remotePlayer1.field"
				   options:nil];
	[remoteFieldView2 bind:@"field"
				  toObject:playersController
			   withKeyPath:@"remotePlayer2.field"
				   options:nil];
	[remoteFieldView3 bind:@"field"
				  toObject:playersController
			   withKeyPath:@"remotePlayer3.field"
				   options:nil];
	[remoteFieldView4 bind:@"field"
				  toObject:playersController
			   withKeyPath:@"remotePlayer4.field"
				   options:nil];
	[remoteFieldView5 bind:@"field"
				  toObject:playersController
			   withKeyPath:@"remotePlayer5.field"
				   options:nil];
	
	// Clear the chat text
	[self clearChat];
}

- (void)dealloc
{
	// De-register for notifications
	[[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self
																 forKeyPath:[@"values." stringByAppendingString:iTetCurrentKeyConfigNumberPrefKey]];
	
	[currentKeyConfiguration release];
	[currentGameRules release];
	[blockGenerator release];
	
	[blockTimer invalidate];
	
	[super dealloc];
}

#pragma mark -
#pragma mark Interface Actions

#define iTetEndGameAlertTitle			NSLocalizedStringFromTable(@"End Game in Progress?", @"GameViewController", @"Title of 'end game' confirmation alert, displayed when the user selects the 'end game' toolbar button or menu item")
#define iTetEndGameAlertInformativeText	NSLocalizedStringFromTable(@"Are you sure you want to end the game in progress?", @"GameViewController", @"Informative text on 'end game' confirmation alert")
#define iTetEndGameConfirmButtonTitle	NSLocalizedStringFromTable(@"End Game", @"GameViewController", @"Title of button on 'end game' confirmation alert that allows the user to confirm and end the game in progress")

- (IBAction)startStopGame:(id)sender
{
	// Check if a game is already in progress
	if ([self gameplayState] != gameNotPlaying)
	{
		// Confirm with user before ending game
		// If this is an offline game, make sure the game is paused
		BOOL offlineGameShouldBeResumed = NO;
		if ([self offlineGame] && ([self gameplayState] != gamePaused))
		{
			[self pauseGame];
			offlineGameShouldBeResumed = YES;
		}
		
		// Create a confirmation dialog
		NSAlert* dialog = [[[NSAlert alloc] init] autorelease];
		[dialog setMessageText:iTetEndGameAlertTitle];
		[dialog setInformativeText:iTetEndGameAlertInformativeText];
		[dialog addButtonWithTitle:iTetEndGameConfirmButtonTitle];
		[dialog addButtonWithTitle:iTetContinuePlayingButtonTitle];
		
		// Run the dialog as a window-modal sheet
		[dialog beginSheetModalForWindow:[windowController window]
						   modalDelegate:self
						  didEndSelector:@selector(stopGameAlertDidEnd:returnCode:resumeOfflineGameOnCancel:)
							 contextInfo:[[NSNumber alloc] initWithBool:offlineGameShouldBeResumed]];
	}
	else
	{
		// If we're connected to a server, send a "start game" message
		if ([networkController connectionState] == connected)
		{
			iTetMessage* startMessage = [iTetMessage messageWithMessageType:startStopGameMessage];
			[[startMessage contents] setInteger:[LOCALPLAYER playerNumber]
										 forKey:iTetMessagePlayerNumberKey];
			[[startMessage contents] setInt:startGameRequest
									 forKey:iTetMessageStartStopRequestTypeKey];
			[networkController sendMessage:startMessage];
		}
		// Otherwise, start an offline game
		else
		{
			// Create a local player
			[playersController setLocalPlayer:[iTetLocalPlayer playerWithNickname:NSFullUserName()
																		   number:1]];
			
			// Switch to the game tab
			[windowController switchToGameTab:self];
			
			// Start the game
			[self newGameWithPlayers:[NSArray arrayWithObject:LOCALPLAYER]
							   rules:[[NSUserDefaults standardUserDefaults] objectForKey:iTetOfflineGameRulesPrefKey]];
		}
	}
}

#define iTetForfeitGameAlertTitle			NSLocalizedStringFromTable(@"Forfeit Game?", @"GameViewController", @"Title of 'forfeit game' confirmation art, displayed when the user selects the 'forfeit game' toolbar button")
#define iTetForfeitGameAlertInformativeText	NSLocalizedStringFromTable(@"Are you sure you want to forfeit this game?", @"GameViewController", @"Informative text on 'forfeit game' confirmation alert")
#define iTetForfeitGameConfirmButtonTitle	NSLocalizedStringFromTable(@"Forfeit", @"GameViewController", @"Title of button on 'forfeit game' confirmation alert that allows the user to confirm and forfeit the game")

- (IBAction)forfeitGame:(id)sender
{
	// If this is an offline game, make sure the game is paused
	BOOL offlineGameShouldBeResumed = NO;
	if ([self offlineGame] && ([self gameplayState] != gamePaused))
	{
		[self pauseGame];
		offlineGameShouldBeResumed = YES;
	}
	
	// Create a confirmation dialog
	NSAlert* dialog = [[[NSAlert alloc] init] autorelease];
	[dialog setMessageText:iTetForfeitGameAlertTitle];
	[dialog setInformativeText:iTetForfeitGameAlertInformativeText];
	[dialog addButtonWithTitle:iTetForfeitGameConfirmButtonTitle];
	[dialog addButtonWithTitle:iTetContinuePlayingButtonTitle];
	
	// Run the dialog as a window-modal sheet
	[dialog beginSheetModalForWindow:[windowController window]
					   modalDelegate:self
					  didEndSelector:@selector(forfeitDialogDidEnd:returnCode:resumeOfflineGameOnCancel:)
						 contextInfo:[[NSNumber alloc] initWithBool:offlineGameShouldBeResumed]];
}

- (IBAction)pauseResumeGame:(id)sender
{
	// Check if game is already paused
	if ([self gameplayState] == gamePaused)
	{
		// If we are connected to a server, send a message asking to resume play
		if (![self offlineGame])
		{
			iTetMessage* resumeMessage = [iTetMessage messageWithMessageType:pauseResumeGameMessage];
			[[resumeMessage contents] setInteger:[LOCALPLAYER playerNumber]
										  forKey:iTetMessagePlayerNumberKey];
			[[resumeMessage contents] setInt:resumeGameRequest
									  forKey:iTetMessagePauseResumeRequestTypeKey];
			[networkController sendMessage:resumeMessage];
		}
		// Otherwise, if this is an offline game, resume immediately
		else
		{
			// Make sure we are looking at the game tab
			[windowController switchToGameTab:self];
			
			[self resumeGame];
		}
	}
	else
	{
		// If we are connected to a server, send a message asking to pause
		if (![self offlineGame])
		{
			iTetMessage* pauseMessage = [iTetMessage messageWithMessageType:pauseResumeGameMessage];
			[[pauseMessage contents] setInteger:[LOCALPLAYER playerNumber]
										  forKey:iTetMessagePlayerNumberKey];
			[[pauseMessage contents] setInt:pauseGameRequest
									  forKey:iTetMessagePauseResumeRequestTypeKey];
			[networkController sendMessage:pauseMessage];
		}
		// Otherwise, if this is an offline game, pause immediately
		else
		{
			[self pauseGame];
		}
	}
}

- (IBAction)submitChatMessage:(id)sender
{
	// Check that there is chat text to send
	NSString* messageText = [messageField stringValue];
	if ([messageText length] == 0)
		return;
	
	// Create a message
	iTetMessage* message = [iTetMessage messageWithMessageType:gameChatMessage];
	[[message contents] setObject:[LOCALPLAYER nickname]
						   forKey:iTetMessagePlayerNicknameKey];
	[[message contents] setObject:messageText
						   forKey:iTetMessageChatContentsKey];
	[networkController sendMessage:message];
	
	// Do not add the message to our chat view; the server will echo it back to us
	
	// Clear the message field
	[messageField setStringValue:@""];
	
	// If there is a game in progress, return first responder status to the field
	if (([self gameplayState] == gamePlaying) && [LOCALPLAYER isPlaying])
		[[windowController window] makeFirstResponder:localFieldView];
}

#pragma mark -
#pragma mark Modal Sheet Callbacks

- (void)stopGameAlertDidEnd:(NSAlert*)dialog
				 returnCode:(NSInteger)returnCode
  resumeOfflineGameOnCancel:(NSNumber*)resumeGame
{
	BOOL offlineGameShouldBeResumed = [resumeGame boolValue];
	[resumeGame release];
	
	// If the user pressed "continue playing", cancel ending the game
	if (returnCode == NSAlertSecondButtonReturn)
	{
		// If this is an offline game, and it needs to be resumed, do so
		if ([self offlineGame] && offlineGameShouldBeResumed)
		{
			[self resumeGame];
		}
		
		return;
	}
	
	// If we are connected to a server, send a "stop game" message
	if (![self offlineGame])
	{
		iTetMessage* stopMessage = [iTetMessage messageWithMessageType:startStopGameMessage];
		[[stopMessage contents] setInteger:[LOCALPLAYER playerNumber]
									forKey:iTetMessagePlayerNumberKey];
		[[stopMessage contents] setInt:stopGameRequest
								forKey:iTetMessageStartStopRequestTypeKey];
		[networkController sendMessage:stopMessage];
	}
	// Otherwise, if this is an offline game, abort immediately
	else
	{
		[self endGame];
	}
}

- (void)forfeitDialogDidEnd:(NSAlert*)dialog
				 returnCode:(NSInteger)returnCode
  resumeOfflineGameOnCancel:(NSNumber*)resumeGame
{
	BOOL offlineGameShouldBeResumed = [resumeGame boolValue];
	[resumeGame release];
	
	// If the user pressed "continue playing", cancel forfeitting
	if (returnCode == NSAlertSecondButtonReturn)
	{
		// If this is an offline game, and it needs to be resumed, do so
		if ([self offlineGame] && offlineGameShouldBeResumed)
		{
			[self resumeGame];
		}
		
		return;
	}
	
	// Forfeit the current game
	[self playerLost];
}

#pragma mark -
#pragma mark Interface Validations

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)item
{
	// Determine which item we are looking at based on its action
	SEL itemAction = [item action];
	
	// If we are connected to a server, get the current operator player
	iTetPlayer* op = nil;
	if (![self offlineGame])
		op = [playersController operatorPlayer];
	
	// "New Game" / "End Game" button/menu item
	if (itemAction == @selector(startStopGame:))
	{
		// Enabled if we are not connected to a server (for offline games) or if we are connected and the local player is the operator
		return (([networkController connectionState] == disconnected) || [op isLocalPlayer]);
	}
	
	// "Forfeit" button/menu item
	if (itemAction == @selector(forfeitGame:))
	{
		// Enabled if the local player is playing in the current game
		return [LOCALPLAYER isPlaying];
	}
	
	// "Pause" / "Resume" button/menu item
	if (itemAction == @selector(pauseResumeGame:))
	{
		// Enabled if there is a game in progress, and it is an offline game or an online game with the local player as operator
		return (([self gameplayState] != gameNotPlaying) && ([self offlineGame] || [op isLocalPlayer]));
	}
	
	return YES;
}

#pragma mark -
#pragma mark Chat

- (void)appendChatLine:(NSString*)line
		fromPlayerName:(NSString*)playerName
{
	[self appendChatLine:[NSString stringWithFormat:@"%@: %@", playerName, line]];
}

- (void)appendChatLine:(NSString*)line
{
	// If the chat view is not empty, add a line separator
	if ([[chatView textStorage] length] > 0)
		[[[chatView textStorage] mutableString] appendFormat:@"%C", NSLineSeparatorCharacter];
	
	// Add the line
	[[[chatView textStorage] mutableString] appendString:line];
	
	// Scroll down
	[chatView scrollRangeToVisible:NSMakeRange([[chatView textStorage] length], 0)];
}

- (void)clearChat
{
	[chatView replaceCharactersInRange:NSMakeRange(0, [[chatView textStorage] length])
							withString:@""];
}

#pragma mark -
#pragma mark Controlling Game State

- (void)newGameWithPlayers:(NSArray*)players
					 rules:(NSDictionary*)rules
{
	// Clear the chat view and list of actions from the last game
	[self clearChat];
	[self clearActions];
	
	// Create the game rules
	[self setCurrentGameRules:rules];
	
	// Set up the players' fields
	for (iTetPlayer* player in players)
	{
		// Set the player's "playing" status
		[player setPlaying:YES];
		
		// Give the player a blank field
		[player setField:[iTetField field]];
		
		// Set the starting level
		[player setLevel:[rules integerForKey:iTetGameRulesStartingLevelKey]];
	}
	
	// If there is a starting stack, give the local player a field with garbage
	if ([rules integerForKey:iTetGameRulesInitialStackHeightKey] > 0)
	{
		// Create the field
		[LOCALPLAYER setField:[iTetField fieldWithStackHeight:[rules integerForKey:iTetGameRulesInitialStackHeightKey]]];
	}
	
	// If this isn't an offline game, send the local player's field to the server
	[self sendFieldUpdate];
	
	// Create a random block generator
	if ([rules intForKey:iTetGameRulesGameVersionKey] == version114)
	{
		blockGenerator = [[iTetSequencedBlockGenerator alloc] initWithBlockFrequenices:[rules objectForKey:iTetGameRulesBlockFrequenciesKey]
																		  sequenceSeed:[rules integerForKey:iTetGameRulesBlockGeneratorSeedKey]];
	}
	else
	{
		blockGenerator = [[iTetRandomBlockGenerator alloc] initWithBlockFrequencies:[rules objectForKey:iTetGameRulesBlockFrequenciesKey]];
	}
	
	// Create the first block to add to the field
	[LOCALPLAYER setNextBlock:[blockGenerator generateNextBlock]];
	
	// Move the block to the field
	[self moveNextBlockToField];
	
	// Create a new specials queue for the local player
	[LOCALPLAYER setSpecialsQueue:[NSMutableArray arrayWithCapacity:[rules integerForKey:iTetGameRulesSpecialCapacityKey]]];
	
	// Reset the local player's cleared lines
	[LOCALPLAYER resetLinesCleared];
	
	// Switch to the game view tab, if not already there
	[windowController switchToGameTab:self];
	
	// Make sure the local player's field is the first responder
	[[windowController window] makeFirstResponder:localFieldView];
	
	// Set the game state to "playing"
	[self setGameplayState:gamePlaying];
}

- (void)pauseGame
{
	// If the game is already paused, do nothing
	if ([self gameplayState] == gamePaused)
		return;
	
	// Set the game state to "paused"
	[self setGameplayState:gamePaused];
	
	// If the local player is still in the game, pause the current block timer
	if ([LOCALPLAYER isPlaying])
		[self pauseBlockTimer];
}

- (void)resumeGame
{
	// If the game is not paused, do nothing
	if ([self gameplayState] != gamePaused)
		return;
	
	// Set the game state to "playing"
	[self setGameplayState:gamePlaying];
	
	// If the local player is in the game, resume the block timer, and give the field first responder status
	if ([LOCALPLAYER isPlaying])
	{
		[self resumeBlockTimer];
		
		// Make sure we're looking at the game tab
		[windowController switchToGameTab:self];
		
		// Give the local player's field first responder status
		[[windowController window] makeFirstResponder:localFieldView];
	}
}

- (void)endGame
{
	// Set the game state to "not playing"
	[self setGameplayState:gameNotPlaying];
	
	// Set all players to "not playing"
	for (iTetPlayer* player in [playersController playerList])
		[player setPlaying:NO];
	
	// Invalidate the block timer
	[blockTimer invalidate];
	blockTimer = nil;
	
	// Clear the falling block
	[LOCALPLAYER setCurrentBlock:nil];
	
	// If we have been playing a local game, remove the local player
	if ([self offlineGame])
		[playersController setLocalPlayer:nil];
	
	// Clear the game rules
	[self setCurrentGameRules:nil];
	[blockGenerator release];
	blockGenerator = nil;
}

#pragma mark -
#pragma mark Key Bindings Key/Value Observation

- (void)observeValueForKeyPath:(NSString*)keyPath
					  ofObject:(id)object
						change:(NSDictionary*)change
					   context:(void *)context
{
	// Change to keyboard configuration; load new bindings from user defaults
	[self setCurrentKeyConfiguration:[iTetKeyConfiguration currentKeyConfiguration]];
}

#pragma mark -
#pragma mark Gameplay Events

- (void)moveCurrentBlockDown
{
	// Move the local player's block down
	iTetBlock* movedBlock = [[LOCALPLAYER currentBlock] blockShiftedDown];
	
	// If the block solidifies, add the (unshifted) block to the field
	if ([[LOCALPLAYER field] blockObstructed:movedBlock] != unobstructed)
	{
		// Invalidate the falling-block timer, if necessary
		[blockTimer invalidate];
		
		// Add the block to the field
		[self solidifyBlock:[LOCALPLAYER currentBlock]];
		
		return;
	}
	
	// Otherwise, assign the shifted block to the local player
	[LOCALPLAYER setCurrentBlock:movedBlock];
	
	// Check if we need a new fall timer
	if (blockTimer == nil)
		[self startBlockFallTimer];
}

- (void)solidifyBlock:(iTetBlock*)block
{
	// Add the block to the local player's field
	iTetField* newField = [[LOCALPLAYER field] fieldBySolidifyingBlock:block];
	
	// Attempt to clear lines on the field
	NSInteger numLines = 0;
	NSArray* specials = nil;
	newField = [newField fieldWithLinesCleared:&numLines
							 retrievedSpecials:&specials];
	while (numLines > 0)
	{
		// Add the lines to the player's counts
		[LOCALPLAYER addLines:numLines];
		
		// If rules specify, copy each collected special for each line cleared
		if ([currentGameRules boolForKey:iTetGameRulesCopyCollectedSpecialsKey])
		{
			for (NSInteger copiesAdded = 0; copiesAdded < numLines; copiesAdded++)
			{
				// Add a copy of each special for each line cleared
				for (NSNumber* special in specials)
				{
					// Check if there is space in the queue
					if ([[LOCALPLAYER specialsQueue] count] >= [currentGameRules unsignedIntegerForKey:iTetGameRulesSpecialCapacityKey])
						goto specialsFull;
					
					// Add to player's queue
					[LOCALPLAYER addSpecialToQueue:special];
				}
			}
		}
		// Otherwise, add only one copy of each special
		else
		{
			for (NSNumber* special in specials)
			{
				// Check if there is space in the queue
				if ([[LOCALPLAYER specialsQueue] count] >= [currentGameRules unsignedIntegerForKey:iTetGameRulesSpecialCapacityKey])
					goto specialsFull;
				
				// Add to player's queue
				[LOCALPLAYER addSpecialToQueue:special];
			}
		}
		
	specialsFull:;
		
		// Check whether to send lines to other players
		if ([currentGameRules boolForKey:iTetGameRulesClassicRulesKey])
		{
			// Determine how many lines to send
			NSInteger linesToSend = 0;
			switch (numLines)
			{
					// For two lines cleared, send one line
				case 2:
					linesToSend = 1;
					break;
					
					// For three lines cleared, send two lines
				case 3:
					linesToSend = 2;
					break;
					
					// For four lines cleared, send four lines
				case 4:
					linesToSend = 4;
					break;
					
					// For one line, send nothing
				default:
					break;
			}
			
			// Send the lines
			if (linesToSend > 0)
				[self sendLines:linesToSend];
		}
		
		// Check for level updates
		NSInteger linesPer = [currentGameRules integerForKey:iTetGameRulesLinesPerLevelKey];
		while ([LOCALPLAYER linesSinceLastLevel] >= linesPer)
		{
			// Increase the level
			[LOCALPLAYER setLevel:([LOCALPLAYER level] + [currentGameRules integerForKey:iTetGameRulesLevelIncreaseKey])];
			
			// Send a level increase message to the server
			[self sendCurrentLevel];
			
			// Decrement the lines cleared since the last level update
			[LOCALPLAYER setLinesSinceLastLevel:([LOCALPLAYER linesSinceLastLevel] - linesPer)];
		}
		
		// Check whether to add specials to the field
		if ([currentGameRules boolForKey:iTetGameRulesSpecialsEnabledKey])
		{
			linesPer = [currentGameRules integerForKey:iTetGameRulesLinesPerSpecialKey];
			while ([LOCALPLAYER linesSinceLastSpecials] >= linesPer)
			{
				// Add specials
				newField = [newField fieldByAddingSpecials:[currentGameRules integerForKey:iTetGameRulesSpecialsAddedKey]
										  usingFrequencies:[currentGameRules objectForKey:iTetGameRulesSpecialFrequenciesKey]];
				
				// Decrement the lines cleared since last specials added
				[LOCALPLAYER setLinesSinceLastSpecials:([LOCALPLAYER linesSinceLastSpecials] - linesPer)];
			}
		}
		
		// Check for additional lines cleared (a very unusual occurrence, but still possible)
		newField = [newField fieldWithLinesCleared:&numLines
								 retrievedSpecials:&specials];
	}
	
	// Update the local player's field
	[LOCALPLAYER setField:newField];
	
	// Send updates to the server
	[self sendFieldUpdate];
	
	// Depending on the protocol, either start the next block immediately, or set a time delay
	if ([currentGameRules intForKey:iTetGameRulesGameTypeKey] == tetrifastProtocol)
	{
		// Spawn the next block immediately
		[self moveNextBlockToField];
	}
	else
	{
		// Remove the current block
		[LOCALPLAYER setCurrentBlock:nil];
		
		// Set a timer to spawn the next block
		[self startNextBlockTimer];
	}
}

- (void)moveNextBlockToField
{
	// Get the local player's next block, and prepare to move it to the field
	iTetBlock* block = [LOCALPLAYER nextBlock];
	
	// Calculate the block's starting position
	IPSCoord blockStartPosition;
	blockStartPosition.row = ((ITET_FIELD_HEIGHT - ITET_BLOCK_HEIGHT) + [block initialRowOffset]);
	blockStartPosition.col = (((ITET_FIELD_WIDTH - ITET_BLOCK_WIDTH)/2) + [block initialColumnOffset]);
	block = [iTetBlock blockWithType:[block type]
						 orientation:[block orientation]
							position:blockStartPosition];
	
	// Check if the block can be moved to the field
	if ([[LOCALPLAYER field] blockObstructed:block] != unobstructed)
	{
		// Player has lost
		[self playerLost];
		return;
	}
	
	// Transfer the block to the field
	[LOCALPLAYER setCurrentBlock:block];
	
	// Generate a new next block
	[LOCALPLAYER setNextBlock:[blockGenerator generateNextBlock]];
	
	// Set the fall timer
	[self startBlockFallTimer];
}

- (void)useSpecial:(iTetSpecialType)special
		  onTarget:(iTetPlayer*)target
		fromSender:(iTetPlayer*)sender
{
	iTetField* newField = nil;
	BOOL playerLost = NO;
	
	// Determine the type of special and its effect on the field
	switch (special)
	{
		case addLine:
			// Add a line to the field
			newField = [[LOCALPLAYER field] fieldByAddingLines:1
														 style:specialStyle 
													playerLost:&playerLost];
			break;
			
		case clearLine:
			// Remove the bottom line from the field
			newField = [[LOCALPLAYER field] fieldByClearingBottomLine];
			break;
			
		case nukeField:
			// Clear the field
			newField = [iTetField field];
			break;
			
		case randomClear:
			// Clear random cells from the field
			newField = [[LOCALPLAYER field] fieldByClearingTenRandomCells];
			break;
			
		case switchField:
			// If the local player is the target, copy the sender's field
			if ([target isLocalPlayer])
				newField = [[sender field] fieldByClearingTopSixRows];
			// If the local player is the sender, copy the target's field
			else
				newField = [[target field] fieldByClearingTopSixRows];
			break;
			
		case clearSpecials:
			// Clear all specials from the field
			newField = [[LOCALPLAYER field] fieldByRemovingAllSpecials];
			break;
			
		case gravity:
			// Apply gravity to the field
			// (Lines may be completed after a gravity special, but they don't count toward the player's lines cleared, and specials aren't collected)
			newField = [[[LOCALPLAYER field] fieldByPullingCellsDown] fieldWithLinesCleared];
			break;
			
		case quakeField:
			// "Quake" the field
			newField = [[LOCALPLAYER field] fieldByRandomlyShiftingRows];
			break;
			
		case blockBomb:
			// "Explode" block bomb blocks
			// (Block bombs may (very rarely) complete lines; see note at "gravity")
			newField = [[[LOCALPLAYER field] fieldByExplodingBlockBombs] fieldWithLinesCleared];
			break;
			
		case classicStyle1:
		case classicStyle2:
		case classicStyle4:
			// Add line(s) to the field
			newField = [[LOCALPLAYER field] fieldByAddingLines:[iTetSpecials classicLinesForSpecialType:special]
														 style:classicStyle 
													playerLost:&playerLost];
			break;
			
		default:
			NSAssert2(NO, @"GameViewController -activateSpecial: called with invalid special type: %c (%d)", special, special);
			break;
	}
	
	// Check if the local player has lost the game
	if (playerLost)
	{
		[self playerLost];
	}
	else
	{
		// Apply changes to local player's field
		[LOCALPLAYER setField:newField];
		
		// Send field changes to the server
		[self sendFieldUpdate];
	}	
}

- (void)playerLost
{
	// If this is an offline game, simply end the game and clean up state
	if ([self offlineGame])
	{
		[self endGame];
		return;
	}
	
	// Otherwise, clean up state for the local player only
	// Clear the falling block
	[LOCALPLAYER setCurrentBlock:nil];
	
	// Give the player a randomly-filled field
	[LOCALPLAYER setField:[iTetField fieldWithRandomContents]];
	
	// Clear the player's specials queue
	[LOCALPLAYER setSpecialsQueue:[NSMutableArray array]];
	
	// Set the local player's status to "not playing"
	[LOCALPLAYER setPlaying:NO];
	
	// Clear the block timer
	[blockTimer invalidate];
	blockTimer = nil;
	
	// Send a "player lost" message to the server, along with the "death field"
	iTetMessage* message = [iTetMessage messageWithMessageType:playerLostMessage];
	[[message contents] setInteger:[LOCALPLAYER playerNumber]
							forKey:iTetMessagePlayerNumberKey];
	[networkController sendMessage:message];
	[self sendFieldUpdate];
}

#pragma mark iTetLocalFieldView Event Delegate Methods

- (void)keyPressed:(iTetKeyNamePair*)key
  onLocalFieldView:(iTetLocalFieldView*)fieldView
{
	// Determine whether the pressed key is bound to a game action
	iTetGameAction action = [currentKeyConfiguration actionForKeyBinding:key];
	
	// If the key is bound to 'game chat,' move first responder to the chat field
	if (action == gameChat)
	{
		// Change first responder
		[[windowController window] makeFirstResponder:messageField];
		return;
	}
	
	// If the game is not in-play, or the local player has lost, ignore any other actions
	if (([self gameplayState] != gamePlaying) || ![LOCALPLAYER isPlaying])
		return;
	
	iTetPlayer* targetPlayer = nil;
	iTetMoveDirection moveDirection = moveRight;
	iTetRotationDirection rotationDirection = rotateClockwise;
	
	// Perform the relevant action
	switch (action)
	{
		case movePieceLeft:
			moveDirection = moveLeft;
			// Fall through
		case movePieceRight:
		{
			// If there's no block on the field, do nothing
			if ([LOCALPLAYER currentBlock] == nil)
				break;
			
			// Attempt to move the local player's block
			iTetBlock* movedBlock = [[LOCALPLAYER currentBlock] blockShiftedInDirection:moveDirection];
			
			// Check if the block's movement is prevented by the bounds or contents of the field
			if ([[LOCALPLAYER field] blockObstructed:movedBlock] == unobstructed)
				[LOCALPLAYER setCurrentBlock:movedBlock];
			
			break;
		}
		case rotatePieceCounterclockwise:
			rotationDirection = rotateCounterclockwise;
			// Fall through
		case rotatePieceClockwise:
		{
			// If there's no block on the field, do nothing
			if ([LOCALPLAYER currentBlock] == nil)
				break;
			
			// Attempt to rotate the local player's block
			iTetBlock* rotatedBlock = [[LOCALPLAYER currentBlock] blockRotatedInDirection:rotationDirection];
			
			// Check if the rotation is prevented by the bounds or contents of the field
			switch ([[LOCALPLAYER field] blockObstructed:rotatedBlock])
			{
				case obstructVert:
				{
					// Attempt to shift the block down to accommodate rotation
					rotatedBlock = [rotatedBlock blockShiftedDown];
					if ([[LOCALPLAYER field] blockObstructed:rotatedBlock] == unobstructed)
					{
						// Assign the rotated and shifted block
						[LOCALPLAYER setCurrentBlock:rotatedBlock];
					}
					break;
				}	
				case obstructHoriz:
				{
					// Attempt to shift the block horizontally to accommodate rotation
					iTetBlock* shiftedBlock = rotatedBlock;
					for (NSInteger i = 0; i < 2; i++)
					{
						// Shift the block left
						shiftedBlock = [shiftedBlock blockShiftedInDirection:moveLeft];
						
						// Check if the block is now clear to rotate
						if ([[LOCALPLAYER field] blockObstructed:shiftedBlock] == unobstructed)
						{
							// Assign the rotated and shifted block
							[LOCALPLAYER setCurrentBlock:shiftedBlock];
							goto successfulShift;
						}
					}
					
					shiftedBlock = rotatedBlock;
					for (NSInteger i = 0; i < 2; i++)
					{
						// Shift the block right
						shiftedBlock = [shiftedBlock blockShiftedInDirection:moveRight];
						
						// Check if the block is now clear to rotate
						if ([[LOCALPLAYER field] blockObstructed:shiftedBlock] == unobstructed)
						{
							// Assign the rotated and shifted block
							[LOCALPLAYER setCurrentBlock:shiftedBlock];
							goto successfulShift;
						}
					}
					
				successfulShift:;
					break;
				}
				default:
					// No obstructions: assign the rotated block to the local player
					[LOCALPLAYER setCurrentBlock:rotatedBlock];
					break;
			}
			
			break;
		}
		case movePieceDown:
		{
			// If there's no block on the field, do nothing
			if ([LOCALPLAYER currentBlock] == nil)
				break;
			
			// Invalidate the fall timer ("move block down" method will create a new one)
			[blockTimer invalidate];
			blockTimer = nil;
			
			// Move the piece down
			[self moveCurrentBlockDown];
			
			break;
		}	
		case dropPiece:
		{
			// If there's no block on the field, do nothing
			if ([LOCALPLAYER currentBlock] == nil)
				break;
			
			// Invalidate the fall timer ("solidify block" method will create the next one)
			[blockTimer invalidate];
			blockTimer = nil;
			
			// Move the block down until it stops
			iTetBlock* droppingBlock = [LOCALPLAYER currentBlock];
			iTetBlock* nextShift = [droppingBlock blockShiftedDown];
			while ([[LOCALPLAYER field] blockObstructed:nextShift] == unobstructed)
			{
				droppingBlock = nextShift;
				nextShift = [droppingBlock blockShiftedDown];
			}
			
			// Solidify the block
			[self solidifyBlock:droppingBlock];
			
			break;
		}
		case discardSpecial:
			// Drop the first special from the local player's queue
			if ([[LOCALPLAYER specialsQueue] count] > 0)
				[LOCALPLAYER dequeueNextSpecial];
			break;
			
		case selfSpecial:
			// Send special to self
			targetPlayer = LOCALPLAYER;
			break;
			
			// Attempt to send special to the player in the specified slot
		case specialPlayer1:
			targetPlayer = [playersController playerNumber:1];
			break;
		case specialPlayer2:
			targetPlayer = [playersController playerNumber:2];
			break;
		case specialPlayer3:
			targetPlayer = [playersController playerNumber:3];
			break;
		case specialPlayer4:
			targetPlayer = [playersController playerNumber:4];
			break;
		case specialPlayer5:
			targetPlayer = [playersController playerNumber:5];
			break;
		case specialPlayer6:
			targetPlayer = [playersController playerNumber:6];
			break;
			
		default:
			// Unrecognized key
			break;
	}
	
	// If we have a target and a special to send, send the special
	if ((targetPlayer != nil) && [targetPlayer isPlaying] && ([[LOCALPLAYER specialsQueue] count] > 0))
	{
		[self sendSpecial:[LOCALPLAYER dequeueNextSpecial]
				 toPlayer:targetPlayer];
	}
}

#pragma mark NSControlTextEditingDelegate Methods

- (BOOL)    control:(NSControl *)control
		   textView:(NSTextView *)textView
doCommandBySelector:(SEL)command
{
	// If this is a 'tab' or 'backtab' keypress, do nothing, instead of changing the first responder
	if ([control isEqual:messageField] && ((command == @selector(insertTab:)) || (command == @selector(insertBacktab:))))
		return YES;
	
	// If the this is an 'escape' keypress in the message field, and we are in-game, clear the message field and return first responder status to the game field
	if ([control isEqual:messageField] && (command == @selector(cancelOperation:)) && ([self gameplayState] == gamePlaying) && [LOCALPLAYER isPlaying])
	{
		// Clear the message field
		[messageField setStringValue:@""];
		
		// Return first responder to the game field
		[[windowController window] makeFirstResponder:localFieldView];
	}
	
	return NO;
}

#pragma mark -
#pragma mark Client-to-Server Events

- (void)sendFieldUpdate
{
	// If this is an offline game, do nothing
	if ([self offlineGame])
		return;
	
	// If the field has no relevant updates, do nothing
	if ([[[LOCALPLAYER field] updateFieldstring] isEqualToString:iTetUnchangedFieldstringPlaceholder])
		return;
	
	// Otherwise, create a field-update message
	iTetMessage* message = [iTetMessage messageWithMessageType:fieldstringMessage];
	[[message contents] setInteger:[LOCALPLAYER playerNumber]
							forKey:iTetMessagePlayerNumberKey];
	[[message contents] setObject:[[LOCALPLAYER field] updateFieldstring]
						   forKey:iTetMessageFieldstringKey];
	
	// Send the message to the server
	[networkController sendMessage:message];
}

- (void)sendCurrentLevel
{
	// If this is an offline game, do nothing
	if ([self offlineGame])
		return;
	
	// Create a message with the local player's level
	iTetMessage* message = [iTetMessage messageWithMessageType:levelUpdateMessage];
	[[message contents] setInteger:[LOCALPLAYER playerNumber]
							forKey:iTetMessagePlayerNumberKey];
	[[message contents] setInteger:[LOCALPLAYER level]
							forKey:iTetMessageLevelNumberKey];
	
	// Send the message to the server
	[networkController sendMessage:message];
}

- (void)sendSpecial:(iTetSpecialType)special
		   toPlayer:(iTetPlayer*)target
{
	// If this isn't an offline game, send a message to the server
	if (![self offlineGame])
	{
		iTetMessage* message = [iTetMessage messageWithMessageType:specialUsedMessage];
		[[message contents] setInteger:[LOCALPLAYER playerNumber]
								forKey:iTetMessagePlayerNumberKey];
		[[message contents] setInteger:((target != nil) ? [target playerNumber] : 0)
								forKey:iTetMessageTargetPlayerNumberKey];
		[[message contents] setInt:special
							forKey:iTetMessageSpecialTypeKey];
		
		[networkController sendMessage:message];
	}
	
	// Perform and record the action
	[self specialUsed:special
			 byPlayer:LOCALPLAYER
			 onPlayer:target];
}

- (void)sendLines:(NSInteger)lines
{
	// If this is an offline game, do nothing
	if ([self offlineGame])
		return;
	
	// Otherwise, convert the lines to a special, and send to everyone
	[self sendSpecial:[iTetSpecials specialTypeForClassicLines:lines]
			 toPlayer:[playersController serverPlayer]];
}

#pragma mark -
#pragma mark Server-to-Client Events

- (void)fieldstringReceived:(NSString*)fieldstring
				  forPlayer:(iTetPlayer*)player
{
	// Check for "no change" updates
	if ((fieldstring == nil) || ([fieldstring length] == 0))
		return;
	
	// Check if this is a partial field update
	unichar firstChar = [fieldstring characterAtIndex:0];
	if ((firstChar >= 0x21) && (firstChar <= 0x2F))
	{
		// Update the player's field with a partial update
		[player setField:[iTetField fieldByApplyingPartialUpdate:fieldstring
														 toField:[player field]]];
	}
	else
	{
		// Give the player a new field created from the fieldstring
		[player setField:[iTetField fieldFromFieldstring:fieldstring]];
	}
}

#define iTetSpecialEventDescriptionFormat		NSLocalizedStringFromTable(@"%@ used on %@ by %@", @"GameViewController", @"Event description message added to the 'game actions' list whenever a special is used by one player on another; tokens in order are: special name, target player's name, sender player's name")
#define iTetSelfSpecialEventDescriptionFormat	NSLocalizedStringFromTable(@"%@ used by %@", @"GameViewController", @"Event description message added to the 'game actions' list whenever a specials is used by a player on his- or herself; tokens in order are: special name, player's name.")
#define iTetLinesAddedEventDescriptionFormat	NSLocalizedStringFromTable(@"%@ added to %@ by %@", @"GameViewController", @"Event description message added to the 'game actions' list whenever lines are added to one or more players' fields; tokens in order are: number of lines, (including the word 'line' or 'lines') target player's name, sender player's name")
#define iTetOneLineAddedFormat					NSLocalizedStringFromTable(@"1 Line", @"GameViewController", @"Token for event description messages describing a single line to be added to a player's field")
#define iTetMultipleLinesAddedFormat			NSLocalizedStringFromTable(@"%d Lines", @"GameViewController", @"Token format for event description messages describing multiple lines to be added to a player's field")
#define iTetServerSenderPlaceholderName			NSLocalizedStringFromTable(@"Server", @"GameViewController", @"Placeholder string used in event description messages on the 'game actions' list when specials are used or lines are added by the server")
#define iTetTargetAllPlaceholderName			NSLocalizedStringFromTable(@"All", @"GameViewController", @"Placeholder string used in event description messages on the 'game actions' list when a special is used on or lines are added to all players in the game")

#define iTetEventBackgroundColorFraction	(0.15)

- (void)specialUsed:(iTetSpecialType)special
		   byPlayer:(iTetPlayer*)sender
		   onPlayer:(iTetPlayer*)target
{
	// Check if this action affects the local player; i.e., if the local player is playing and any of the following are true:
	// - the local player is the target
	// - the special is a switchfield and the local player sent it
	// - the special targets all players, and was not sent by the local player
	BOOL localPlayerAffected = ([LOCALPLAYER isPlaying] &&
								([target isLocalPlayer] ||
								 ((special == switchField) && [sender isLocalPlayer]) ||
								 (([target playerNumber] == 0) && ![sender isLocalPlayer])));
	
	// Perform the action, if applicable
	if (localPlayerAffected)
	{
		[self useSpecial:special
				onTarget:target
			  fromSender:sender];
	}
	
	// Add a description of the event to the list of actions
	NSString* senderName = nil;
	NSString* targetName = nil;
	NSMutableAttributedString* desc = nil;
	NSColor* textColor = nil;
	NSRange attributeRange;
	
	// Check if this was a "use on self" event
	BOOL selfEvent = NO;
	if (![sender isServerPlayer] && [target isEqual:sender])
		selfEvent = YES;
	
	// Determine the sender player's name
	if ([sender isServerPlayer])
		senderName = iTetServerSenderPlaceholderName;
	else
		senderName = [sender nickname];
	
	// Determine the target player's name
	if (!selfEvent)
	{
		if ([target playerNumber] == 0)
			targetName = iTetTargetAllPlaceholderName;
		else
			targetName = [target nickname];
	}
	
	// Determine if the special is a classic-style line add
	NSInteger numLinesAdded = [iTetSpecials classicLinesForSpecialType:special];
	if (numLinesAdded > 0)
	{
		// Describe the number of lines added
		NSString* linesDesc;
		if (numLinesAdded > 1)
			linesDesc = [NSString stringWithFormat:iTetMultipleLinesAddedFormat, numLinesAdded];
		else
			linesDesc = iTetOneLineAddedFormat;
		
		// Create the description string
		desc = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:iTetLinesAddedEventDescriptionFormat, linesDesc, targetName, senderName]
													  attributes:[iTetTextAttributes defaultGameActionsTextAttributes]];
		
		// Find the highlight range and color
		attributeRange = [[desc string] rangeOfString:linesDesc];
		textColor = [iTetTextAttributes linesAddedDescriptionTextColor];
	}
	else
	{
		// Get the name of the special used
		NSString* specialName = [iTetSpecials nameForSpecialType:special];
		
		// Create the description string
		if (![self offlineGame])
		{
			if (selfEvent)
			{
				desc = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:iTetSelfSpecialEventDescriptionFormat, specialName, senderName]
															  attributes:[iTetTextAttributes defaultGameActionsTextAttributes]];
			}
			else
			{
				desc = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:iTetSpecialEventDescriptionFormat, specialName, targetName, senderName]
															  attributes:[iTetTextAttributes defaultGameActionsTextAttributes]];
			}
		}
		else
		{
			desc = [[NSMutableAttributedString alloc] initWithString:specialName
														  attributes:[iTetTextAttributes defaultGameActionsTextAttributes]];
		}

		// Find the highlight range and color
		attributeRange = [[desc string] rangeOfString:specialName];
		if ([iTetSpecials specialIsPositive:special])
			textColor = [iTetTextAttributes goodSpecialDescriptionTextColor];
		else
			textColor = [iTetTextAttributes badSpecialDescriptionTextColor];
	}
	
	// Apply bold and color to the chosen highlight range
	[desc applyFontTraits:NSBoldFontMask
					range:attributeRange];
	[desc addAttributes:[NSDictionary dictionaryWithObject:textColor
													forKey:NSForegroundColorAttributeName]
				  range:attributeRange];
	
	// Bold the sender and (if applicable) target names
	if (![self offlineGame])
	{
		[desc applyFontTraits:NSBoldFontMask
						range:[[desc string] rangeOfString:senderName
												   options:NSBackwardsSearch]];
		if (!selfEvent)
		{
			[desc applyFontTraits:NSBoldFontMask
							range:[[desc string] rangeOfString:targetName]];
		}
	}
	
	// If the local player was affected, add a background color
	if (localPlayerAffected)
	{
		[desc addAttributes:[NSDictionary dictionaryWithObject:[[NSColor whiteColor] blendedColorWithFraction:iTetEventBackgroundColorFraction
																									  ofColor:textColor]
														forKey:NSBackgroundColorAttributeName]
					  range:NSMakeRange(0, [desc length])];
	}
	
	// Record the event
	[self appendEventDescription:desc];
	[desc release];
}

#pragma mark -
#pragma mark Event Descriptions

- (void)appendEventDescription:(NSAttributedString*)description
{
	// Add the line
	[[actionListView textStorage] appendAttributedString:description];
	
	// Add a line separator
	[[[actionListView textStorage] mutableString] appendFormat:@"%C", NSParagraphSeparatorCharacter];
	
	// Scroll the view to ensure the line is visible
	[actionListView scrollRangeToVisible:NSMakeRange([[actionListView textStorage] length], 0)];
}

- (void)clearActions
{
	[actionListView replaceCharactersInRange:NSMakeRange(0, [[actionListView textStorage] length])
								  withString:@""];
}

#pragma mark -
#pragma mark Timers

#define TETRINET_NEXT_BLOCK_DELAY	1.0

- (void)startNextBlockTimer
{
	// Create a timer to spawn the next block
	blockTimer = [NSTimer timerWithTimeInterval:TETRINET_NEXT_BLOCK_DELAY
										 target:self
									   selector:@selector(timerFired:)
									   userInfo:[NSNumber numberWithInt:nextBlockTimer]
										repeats:NO];
	
	// Attach the timer to the current run loop
	[[NSRunLoop currentRunLoop] addTimer:blockTimer
								 forMode:NSDefaultRunLoopMode];
}

- (void)startBlockFallTimer
{	
	// Create a timer to move the current block down
	blockTimer = [NSTimer timerWithTimeInterval:blockFallDelayForLevel([LOCALPLAYER level])
										 target:self
									   selector:@selector(timerFired:)
									   userInfo:[NSNumber numberWithInt:blockFallTimer]
										repeats:YES];
	
	// Attach the timer to the current run loop
	[[NSRunLoop currentRunLoop] addTimer:blockTimer
								 forMode:NSDefaultRunLoopMode];
}

- (void)pauseBlockTimer
{
	// Timers cannot be paused, so we will instead invalidate the existing timer and create a new one when the game is resumed
	// Record the time until next firing
	timeUntilNextTimerFire = [[blockTimer fireDate] timeIntervalSinceNow];
	
	// Record the type of timer
	lastTimerType = [[blockTimer userInfo] intValue];
	
	// Invalidate and nil the timer
	[blockTimer invalidate];
	blockTimer = nil;
}

- (void)resumeBlockTimer
{
	// Create a timer with a firing date calculated from the time recorded when the game was paused
	BOOL timerRepeats = (lastTimerType == blockFallTimer);
	blockTimer = [[[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:timeUntilNextTimerFire]
										   interval:blockFallDelayForLevel([LOCALPLAYER level])
											 target:self
										   selector:@selector(timerFired:)
										   userInfo:[NSNumber numberWithInt:lastTimerType]
											repeats:timerRepeats] autorelease];
	
	// Attach the timer to the current run loop
	[[NSRunLoop currentRunLoop] addTimer:blockTimer
								 forMode:NSDefaultRunLoopMode];
}

- (void)timerFired:(NSTimer*)timer
{
	switch ([[timer userInfo] intValue])
	{
		case nextBlockTimer:
			[self moveNextBlockToField];
			break;
			
		case blockFallTimer:
			[self moveCurrentBlockDown];
			break;
	}
}

#define ITET_MAX_DELAY_TIME				(1.005)
#define ITET_DELAY_REDUCTION_PER_LEVEL	(0.01)
#define ITET_MIN_DELAY_TIME				(0.005)

NSTimeInterval blockFallDelayForLevel(NSInteger level)
{
	NSTimeInterval time = ITET_MAX_DELAY_TIME - (level * ITET_DELAY_REDUCTION_PER_LEVEL);
	
	if (time < ITET_MIN_DELAY_TIME)
		return ITET_MIN_DELAY_TIME;
	
	return time;
}

#pragma mark -
#pragma mark Accessors

@synthesize currentGameRules;

- (BOOL)offlineGame
{
	return [currentGameRules boolForKey:iTetGameRulesOfflineGameKey];
}

#define iTetNewGameMenuItemTitle	NSLocalizedStringFromTable(@"Begin New Game", @"GameViewController", @"Title of menu item used to start a new game")
#define iTetNewGameButtonTitle		NSLocalizedStringFromTable(@"New Game", @"GameViewController", @"Title of toolbar button used to start a new game")

#define iTetPauseGameMenuItemTitle	NSLocalizedStringFromTable(@"Pause Current Game", @"GameViewController", @"Title of menu item used to pause a game in progress")
#define iTetPauseGameButtonTitle	NSLocalizedStringFromTable(@"Pause", @"GameViewController", @"Title of toolbar button used to pause a game in progress")

#define iTetResumeGameMenuItemTitle	NSLocalizedStringFromTable(@"Resume Paused Game", @"GameViewController", @"Title of menu item used to resume a paused game")
#define iTetResumeGameButtonTitle	NSLocalizedStringFromTable(@"Resume", @"GameViewController", @"Title of toolbar button used to resume a paused game")

#define iTetEndGameMenuItemTitle	NSLocalizedStringFromTable(@"End Current Game...", @"GameViewController", @"Title of menu item used to end a game in progress")
#define iTetEndGameButtonTitle		NSLocalizedStringFromTable(@"End Game", @"GameViewController", @"Title of toolbar button used to end a game in progress")

- (void)setGameplayState:(iTetGameplayState)newState
{
	if (gameplayState == newState)
		return;
	
	switch (newState)
	{
		case gameNotPlaying:
			// Reset the "end game" menu and toolbar items
			[gameMenuItem setTitle:iTetNewGameMenuItemTitle];
			[gameMenuItem setKeyEquivalent:@"n"];
			[gameButton setLabel:iTetNewGameButtonTitle];
			[gameButton setImage:[NSImage imageNamed:@"Play Green Button"]];
			
			// If the game was paused, reset the "resume" menu and toolbar items
			if (gameplayState == gamePaused)
			{
				[pauseMenuItem setTitle:iTetPauseGameMenuItemTitle];
				[pauseButton setLabel:iTetPauseGameButtonTitle];
				[pauseButton setImage:[NSImage imageNamed:@"Pause Blue Button"]];
			}
			
			break;
		
		case gamePaused:
			// Change the "pause" toolbar and menu items to "resume" items
			[pauseMenuItem setTitle:iTetResumeGameMenuItemTitle];
			[pauseButton setLabel:iTetResumeGameButtonTitle];
			[pauseButton setImage:[NSImage imageNamed:@"Play Blue Button"]];
			
			break;
			
		case gamePlaying:
			// Change the "new game" menu and toolbar items to "end game" items
			[gameMenuItem setTitle:iTetEndGameMenuItemTitle];
			[gameMenuItem setKeyEquivalent:@"e"];
			[gameButton setLabel:iTetEndGameButtonTitle];
			[gameButton setImage:[NSImage imageNamed:@"Stop Red Button"]];
			
			// If the game was paused, reset the "resume" menu and toolbar items
			if (gameplayState == gamePaused)
			{
				[pauseMenuItem setTitle:iTetPauseGameMenuItemTitle];
				[pauseButton setLabel:iTetPauseGameButtonTitle];
				[pauseButton setImage:[NSImage imageNamed:@"Pause Blue Button"]];
			}
			
			break;
	}
	
	[self willChangeValueForKey:@"gameplayState"];
	gameplayState = newState;
	[self didChangeValueForKey:@"gameplayState"];
}
@synthesize gameplayState;

- (BOOL)gameInProgress
{
	return ([self gameplayState] == gamePlaying) || ([self gameplayState] == gamePaused);
}

- (void)setCurrentKeyConfiguration:(iTetKeyConfiguration*)config
{
	[config retain];
	[currentKeyConfiguration release];
	currentKeyConfiguration = config;
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
	if ([key isEqualToString:@"gameplayState"])
		return NO;
	
	return [super automaticallyNotifiesObserversForKey:key];
}

+ (NSSet*)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
	NSSet* keys = [super keyPathsForValuesAffectingValueForKey:key];
	
	if ([key isEqualToString:@"gameInProgress"])
		keys = [keys setByAddingObject:@"gameplayState"];
	
	return keys;
}

@end
