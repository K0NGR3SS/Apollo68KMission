*===========================================================
* Title      : Apollo 68K Mission
* Written by : Nazariy Buryak
* Date       : 18/02/2025
* Description: An Apollo 11-style moon landing game made
*              entirely in Motorola 68000 assembly for the
*              Easy68K simulator. The player guides the
*              Saturn V through 4 phases: launch, docking,
*              trans-lunar flight, and lunar landing.
*
* How it works:
*   - TRAP #15 is the Easy68K I/O trap. The task number
*     goes in D0, and different tasks do different things:
*       Task  5 = Read a key from keyboard (waits, echoes)
*       Task  7 = Check if a key is pressed (non-blocking)
*       Task 11 = Set cursor position (col<<8 | row in D1)
*       Task 12 = Clear the entire screen
*       Task 14 = Print a null-terminated string from A1
*       Task 23 = Pause for D1 milliseconds
*       Task 70 = Play a WAV sound file (path in A1)
*===========================================================

    ORG $1000

*===========================================================
* CONSTANTS
*===========================================================

; --- Game States ---
; The game has 5 phases. STATE holds which one we're in.
PAD_STATE       EQU 0       ; Phase 0: Sitting on the launch pad
FLY_STATE       EQU 1       ; Phase 1: Flying up to orbit
DOCK_STATE      EQU 2       ; Phase 2: Docking CSM with LM
FLY_DOCKED      EQU 3       ; Phase 3: Flying to the Moon
LAND_STAGE      EQU 4       ; Phase 4: Landing on the Moon

; --- Sprite Layout ---
LM_ROW          EQU 5       ; Row where the LM sits during docking
SPRITE_H        EQU 5       ; Most sprites are 5 rows tall

; --- Landing Module (LMU) Setup ---
LMU_START_X     EQU 70      ; LM starts in the right side of the screen
LMU_START_Y     EQU 2       ; LM starts near the top of the screen
GRAVITY         EQU 1       ; How much gravity pulls down each frame
SURFACE_Y       EQU 29      ; Screen row where the moon surface is drawn
LANDING_ZONE_X1 EQU 9       ; Left edge of the safe flat landing zone
LANDING_ZONE_X2 EQU 49      ; Right edge of the safe flat landing zone
FRAME_DELAY     EQU 90      ; Milliseconds between frames during landing
LM_WIDTH        EQU 8       ; How wide the LM sprite is (in columns)
LM_LAND_H       EQU 5       ; How tall the landing LM sprite is (in rows)

; --- Fuel Amounts ---
; Each stage burns fuel every frame. When fuel hits 0, you fail.
STAGE0_FUEL     EQU 130     ; Fuel for stage 0 (full Saturn V rocket)
STAGE1_FUEL     EQU 100     ; Fuel for stage 1 (upper stage after 1st sep)
STAGE2_FUEL     EQU 75      ; Fuel for stage 2 (coasting to orbit)
SEP0_MIN_FUEL   EQU 10      ; Fuel must be this low before you can safely separate stage 0
SEP1_MIN_FUEL   EQU 10      ; Fuel must be this low before you can safely separate stage 1
LAND_FUEL_MAX   EQU 15      ; Total fuel units for the landing phase

*===========================================================
* VARIABLES
* These live in RAM at address $4000 and change during play
*===========================================================
    ORG $4000

STATE:          DC.B    0   ; Which game phase we're in (0-4)
                DS.B    1   ; Extra byte so the next word starts on an even address

; --- Position and Altitude ---
ALT:            DC.W    0   ; Current altitude (goes up as rocket flies)
CSM_X:          DC.W    10  ; CSM column on screen
OLD_CSM_X:      DC.W    10  ; Where CSM was last frame (so we can erase it)
CSM_Y:          DC.W    12  ; CSM row on screen
OLD_CSM_Y:      DC.W    12  ; Where CSM was last frame (for erasing)
LM_X:           DC.W    40  ; LM column during docking
DOCKED_ALT:     DC.W    0   ; How far the docked craft has flown toward Moon
LANDING_INIT:   DC.W    0   ; Set to 1 after landing phase is set up (so we only init once)

; --- Landing Module Physics ---
; These track the LM position and speed during the landing phase
LMU_X:          DC.W    0   ; LM current column position
LMU_Y:          DC.W    0   ; LM current row position
LMU_VX:         DC.W    0   ; LM horizontal speed (negative = left, positive = right)
LMU_VY:         DC.W    0   ; LM vertical speed (positive = falling down)
OLD_LMU_X:      DC.W    0   ; LM previous column (for erasing old sprite)
OLD_LMU_Y:      DC.W    0   ; LM previous row (for erasing old sprite)

PWD_BUF:        DS.B    8   ; Scratch space used by PRINT_WORD_DEC to build number strings

; --- Flight and Fuel Tracking ---
FLY_INIT:       DC.W    0   ; Set to 1 after the flight phase is set up
FLY_FUEL:       DC.W    0   ; How much fuel is left in the current stage
LAND_FUEL:      DC.W    0   ; How much landing fuel is left
STAGE_SEP:      DC.W    0   ; Which sub-stage: 0=first, 1=second, 2=coasting
DISOBEYED:      DC.W    0   ; Set to 1 if player ignored Houston's warning
COAST_CTR:      DC.W    0   ; Counts frames after disobeying (if it gets too high, you fail)
PAD_ROW:        DC.W    0   ; Tracks which row of the launch pad is being erased in animation
*===========================================================
* START - Entry Point
* This is where the program begins executing.
* It shows the welcome screen, then enters the main loop
* which checks the current game state and jumps to the
* right phase handler.
*===========================================================
    ORG $1000

START:
    BSR     CLEAR_SCREEN     ; Wipe the screen clean

    ; Play the game intro sound effect
    LEA     SND_ENTRY,A1     ; Load the sound file path into A1
    BSR     PLAY_WAV         ; Play it

    ; Show the welcome screen
    LEA     SCR_WELCOME,A2   ; Load the welcome screen line table
    BSR     PHASE_SCREEN     ; Display it and wait for P or Q

    ; Show the Phase 1 briefing (tells player what to do)
    LEA     SCR_PHASE1,A2    ; Load Phase 1 instruction screen
    BSR     PHASE_SCREEN     ; Display it and wait for P or Q

*-----------------------------------------------------------
* MAIN LOOP
* This runs forever. It checks what phase (STATE) the game
* is in, and jumps to the right section to handle it.
*-----------------------------------------------------------
MAIN_LOOP:
    MOVE.B  STATE,D0         ; Get the current game state

    CMP.B   #PAD_STATE,D0    ; Are we on the launch pad?
    BEQ     DO_PAD           ; Yes -> go to pad phase

    CMP.B   #FLY_STATE,D0    ; Are we flying to orbit?
    BEQ     DO_FLY           ; Yes -> go to flight phase

    CMP.B   #DOCK_STATE,D0   ; Are we docking?
    BEQ     DO_DOCK          ; Yes -> go to docking phase

    CMP.B   #FLY_DOCKED,D0   ; Are we flying to the Moon?
    BEQ     DO_FLY_DOCKED    ; Yes -> go to trans-lunar phase

    CMP.B   #LAND_STAGE,D0   ; Are we landing on the Moon?
    BEQ     DO_LANDING        ; Yes -> go to landing phase

    BRA     END_GAME         ; Unknown state -> end the game

*===========================================================
* PHASE 0: PRE-LAUNCH (Launch Pad)
* The rocket sits on the pad. Player sees the Saturn V
* next to the launch tower. Press W to ignite and lift off.
* The gantry/tower scrolls away as the rocket launches.
*===========================================================
DO_PAD:
    BSR     CLEAR_SCREEN         ; Clear everything
    BSR     SHOW_FLY_STATS       ; Show altitude and fuel at the top
    BSR     DRAW_STARS           ; Draw some stars in the background
    BSR     DRAW_PAD_ROCKET      ; Draw the rocket on the pad (no flames yet)
    BSR     DRAW_LAUNCH_PAD      ; Draw the launch tower next to the rocket

    ; Show "W to Lift Off!" prompt above the rocket (row 3, col 36)
    MOVE.W  #$2403,D1            ; Cursor position: col=36, row=3
    MOVE.B  #11,D0               ; Task 11 = set cursor position
    TRAP    #15
    LEA     PROMPT_LAUNCH,A1     ; Load the prompt text
    MOVE.B  #14,D0               ; Task 14 = print string
    TRAP    #15

; --- Wait for player to press W ---
PAD_WAIT:
    MOVE.B  #7,D0                ; Task 7 = check if any key is pressed
    TRAP    #15
    TST.B   D1                   ; Was a key pressed? (0 = no)
    BEQ     PAD_WAIT             ; No key yet, keep waiting

    MOVE.B  #5,D0                ; Task 5 = read the key (with echo)
    TRAP    #15
    CMP.B   #'w',D1              ; Is it 'w'?
    BNE     PAD_WAIT             ; Not 'w', keep waiting

    ; --- Liftoff! ---

    ; Play the ignition countdown sound
    LEA     SND_IGNITION,A1      ; Load ignition sound path
    BSR     PLAY_WAV             ; Play it

    ; Erase the "W to Lift Off!" prompt (replace with blanks)
    MOVE.W  #$2403,D1            ; Same position as the prompt
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1    ; A line of spaces to cover the text
    MOVE.B  #14,D0
    TRAP    #15

    ; Erase the old pad rocket (it had no flames)
    ; Loop through 32 rows starting at row 5, col 38
    MOVE.W  #5,D3                ; D3 = current row (start at row 5)
    MOVE.W  #32,D2               ; D2 = how many rows to erase
ERASE_PAD_RKT:
    MOVE.W  #38,D1               ; Start with column 38
    LSL.W   #8,D1                ; Shift column into upper byte (col<<8)
    OR.B    D3,D1                ; Put row in lower byte -> D1 = col<<8 | row
    MOVE.B  #11,D0               ; Set cursor to this position
    TRAP    #15
    LEA     BLANK_ROCKET,A1      ; Print blank spaces over the rocket
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3                ; Next row
    SUBQ.W  #1,D2                ; One less row to do
    BNE     ERASE_PAD_RKT        ; Keep going until all rows erased

    ; Draw the full rocket WITH exhaust flames (1 row higher, at row 4)
    LEA     PTR_SATURN,A0        ; Pointer table for full Saturn V sprite
    MOVE.W  #33,D2               ; 33 rows tall (rocket + flames)
    MOVE.W  #4,D3                ; Start at row 4
    MOVE.W  #38,D4               ; Column 38
    BSR     DRAW_SPRITE           ; Draw it!

    ; --- Launch pad scroll animation ---
    ; The launch tower disappears row by row from top to bottom,
    ; making it look like the rocket is lifting off.
    MOVE.W  #5,PAD_ROW           ; Start erasing from row 5 (top of pad)
PAD_SCROLL:
    ; Erase one row of the launch tower at column 53
    MOVE.W  PAD_ROW,D3           ; Get current row to erase
    MOVE.W  #53,D1               ; Tower is at column 53
    LSL.W   #8,D1                ; Shift to upper byte
    OR.B    D3,D1                ; Combine with row
    MOVE.B  #11,D0               ; Set cursor
    TRAP    #15
    LEA     BLANK_ROCKET,A1      ; Print blanks to erase the tower row
    MOVE.B  #14,D0
    TRAP    #15

    ; Each row erased = 1 more altitude gained
    ADDQ.W  #1,ALT               ; Increase altitude by 1
    BSR     SHOW_FLY_STATS       ; Update the stats display

    ADDQ.W  #1,PAD_ROW           ; Move to next row
    CMP.W   #37,PAD_ROW          ; Have we erased all 32 rows (5 to 36)?
    BGE     PAD_SCROLL_DONE      ; Yes -> done with animation

    ; Small delay between rows for smooth animation
    MOVE.L  #5,D1                ; 5 milliseconds
    MOVE.B  #23,D0               ; Task 23 = pause
    TRAP    #15
    BRA     PAD_SCROLL           ; Do next row

PAD_SCROLL_DONE:
    ; Erase the rocket we drew at row 4 (clean up before next phase)
    MOVE.W  #4,D3                ; Start from row 4
    MOVE.W  #33,D2               ; 33 rows to erase
ERASE_LAUNCH_RKT:
    MOVE.W  #38,D1               ; Column 38
    LSL.W   #8,D1                ; Shift column to upper byte
    OR.B    D3,D1                ; Add row to lower byte
    MOVE.B  #11,D0               ; Set cursor position
    TRAP    #15
    LEA     BLANK_ROCKET,A1      ; Print blanks
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3                ; Next row
    SUBQ.W  #1,D2                ; Decrement counter
    BNE     ERASE_LAUNCH_RKT     ; Keep going

    ; All done! Clear screen and move to the flying phase
    BSR     CLEAR_SCREEN
    MOVE.B  #FLY_STATE,STATE     ; Set state to Phase 1 (orbital ascent)
    BRA     MAIN_LOOP            ; Go back to main loop

*===========================================================
* PHASE 1: ORBITAL ASCENT
* The rocket flies upward through 3 sub-stages:
*   Stage 0: Full rocket burns fuel. Press W to separate.
*   Stage 1: Upper stage burns fuel. Press W to separate.
*   Stage 2: Coast upward to altitude 320.
* If you separate too early, Houston warns you.
* If you ignore Houston, you might fail later.
* Altitude must reach 320 to go to the docking phase.
*===========================================================
DO_FLY:
    ; --- One-time setup (only runs the first time) ---
    TST.W   FLY_INIT             ; Has this phase been initialized?
    BNE     SKIP_FLY_INIT        ; Yes -> skip setup

    ; Set up initial values for the flight
    MOVE.W  #STAGE0_FUEL,FLY_FUEL ; Fill up fuel for stage 0
    CLR.W   STAGE_SEP            ; Start at sub-stage 0
    CLR.W   DISOBEYED            ; Player hasn't disobeyed Houston yet
    CLR.W   COAST_CTR            ; Reset the disobey timer
    MOVE.W  #1,FLY_INIT          ; Mark as initialized

    BSR     DRAW_STARS           ; Draw star background
    BSR     DRAW_FULL_ROCKET     ; Draw the full Saturn V with flames

    ; Show "Press W to separate stage 1!" at row 20
    MOVE.W  #$0014,D1            ; Cursor: col=0, row=20
    MOVE.B  #11,D0
    TRAP    #15
    LEA     SEP_MSG,A1           ; The separation prompt text
    MOVE.B  #14,D0
    TRAP    #15

SKIP_FLY_INIT:
    ADDQ.W  #1,ALT               ; Altitude goes up by 1 each frame

    ; Check which sub-stage we're in and jump there
    MOVE.W  STAGE_SEP,D0
    CMP.W   #1,D0                ; Sub-stage 1?
    BEQ     FLY_STAGE1
    CMP.W   #2,D0                ; Sub-stage 2 (coasting)?
    BEQ     FLY_STAGE2

    ; ======= STAGE 0: Full rocket burning =======
    ; Burns fuel each frame. Player presses W to separate.

    SUBQ.W  #1,FLY_FUEL          ; Burn one unit of fuel
    MOVE.W  FLY_FUEL,D0
    BLE     FLY_FUEL_OUT         ; Out of fuel? -> mission fails

    ; Check if player pressed a key (non-blocking)
    MOVE.B  #7,D0                ; Task 7 = is a key pressed?
    TRAP    #15
    TST.B   D1                   ; 0 = no key
    BEQ     FLY_S0_DELAY         ; No key -> just keep flying

    MOVE.B  #5,D0                ; Task 5 = read the key
    TRAP    #15
    CMP.B   #'w',D1              ; Did they press W?
    BNE     FLY_S0_DELAY         ; Nope -> keep flying

    ; --- Player pressed W: check if separation is allowed ---
    ; Fuel must be low enough (burned enough) for a safe separation
    MOVE.W  FLY_FUEL,D0
    CMP.W   #SEP0_MIN_FUEL,D0    ; Is fuel low enough?
    BLE     FLY_S0_DO_SEP        ; Yes -> do the separation

    ; --- Too early! Houston sends a warning ---
    ; Show Houston's warning message on rows 21-22
    MOVE.W  #$0015,D1            ; Row 21
    MOVE.B  #11,D0
    TRAP    #15
    LEA     HOUSTON_MSG,A1       ; "Eagle its Houston, do not proceed..."
    MOVE.B  #14,D0
    TRAP    #15

    MOVE.W  #$0016,D1            ; Row 22
    MOVE.B  #11,D0
    TRAP    #15
    LEA     HOUSTON_OPT,A1       ; "y=Proceed  n=Keep Flying"
    MOVE.B  #14,D0
    TRAP    #15

    ; Play the Houston warning sound
    LEA     SND_SAYAGAIN,A1
    BSR     PLAY_WAV

; Wait for player to choose Y (disobey) or N (listen)
FLY_S0_HWAIT:
    MOVE.B  #7,D0                ; Check for key press
    TRAP    #15
    TST.B   D1
    BEQ     FLY_S0_HWAIT         ; No key -> keep waiting
    MOVE.B  #5,D0                ; Read the key
    TRAP    #15
    CMP.B   #'y',D1              ; Y = disobey Houston
    BEQ     FLY_S0_DISOBEY
    CMP.B   #'n',D1              ; N = listen to Houston, keep flying
    BEQ     FLY_S0_HBACK
    BRA     FLY_S0_HWAIT         ; Other key -> ask again

FLY_S0_DISOBEY:
    MOVE.W  #1,DISOBEYED         ; Remember that player disobeyed
    BRA     FLY_S0_DO_SEP        ; Do the separation anyway

FLY_S0_HBACK:
    ; Player chose to listen - erase the warning text and resume
    MOVE.W  #$0015,D1            ; Erase row 21
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  #$0016,D1            ; Erase row 22
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    BRA     FLY_S0_DELAY         ; Go back to flying

; --- Actually separate stage 0 ---
FLY_S0_DO_SEP:
    BSR     ERASE_ROCKET         ; Erase the full rocket from screen

    ; Erase all prompt/warning text (rows 20-22)
    MOVE.W  #$0014,D1            ; Row 20
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  #$0015,D1            ; Row 21
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  #$0016,D1            ; Row 22
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15

    ; Move to sub-stage 1 with fresh fuel
    MOVE.W  #1,STAGE_SEP         ; Now in sub-stage 1
    MOVE.W  #STAGE1_FUEL,FLY_FUEL ; Fill up fuel for stage 1

    ; Draw the new smaller rocket (after bottom stage dropped off)
    BSR     DRAW_STARS
    BSR     DRAW_FIRST_SEP       ; Draw upper-stage rocket

    ; Show the next separation prompt
    MOVE.W  #$0014,D1            ; Row 20
    MOVE.B  #11,D0
    TRAP    #15
    LEA     SEP2_MSG,A1          ; "Press W to separate stage 2!"
    MOVE.B  #14,D0
    TRAP    #15

; --- Frame delay and loop back ---
FLY_S0_DELAY:
    BSR     SHOW_FLY_STATS       ; Update altitude and fuel display
    MOVE.L  #4,D1                ; 4 millisecond delay
    MOVE.B  #23,D0               ; Task 23 = pause
    TRAP    #15
    BRA     DO_FLY               ; Loop back to the top of the flight phase

    ; ======= STAGE 1: Upper stage burning =======
    ; Same logic as Stage 0 but with the smaller rocket.
    ; Player burns fuel and presses W again to separate.
FLY_STAGE1:
    SUBQ.W  #1,FLY_FUEL          ; Burn one unit of fuel
    MOVE.W  FLY_FUEL,D0
    BLE     FLY_FUEL_OUT         ; Out of fuel -> fail

    ; Check for key press (non-blocking)
    MOVE.B  #7,D0
    TRAP    #15
    TST.B   D1
    BEQ     FLY_S1_DELAY         ; No key -> keep flying
    MOVE.B  #5,D0                ; Read the key
    TRAP    #15
    CMP.B   #'w',D1              ; W pressed?
    BNE     FLY_S1_DELAY         ; No -> keep flying

    ; --- Player pressed W: check if separation is allowed ---
    MOVE.W  FLY_FUEL,D0
    CMP.W   #SEP1_MIN_FUEL,D0    ; Is fuel low enough for safe separation?
    BLE     FLY_S1_DO_SEP        ; Yes -> do it

    ; --- Too early! Houston sends another warning ---
    MOVE.W  #$0015,D1            ; Row 21
    MOVE.B  #11,D0
    TRAP    #15
    LEA     HOUSTON_MSG,A1       ; Warning message
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  #$0016,D1            ; Row 22
    MOVE.B  #11,D0
    TRAP    #15
    LEA     HOUSTON_OPT,A1       ; y/n choice
    MOVE.B  #14,D0
    TRAP    #15
    LEA     SND_SAYAGAIN,A1      ; Play warning sound
    BSR     PLAY_WAV

; Wait for Y or N
FLY_S1_HWAIT:
    MOVE.B  #7,D0
    TRAP    #15
    TST.B   D1
    BEQ     FLY_S1_HWAIT
    MOVE.B  #5,D0
    TRAP    #15
    CMP.B   #'y',D1              ; Y = disobey
    BEQ     FLY_S1_DISOBEY
    CMP.B   #'n',D1              ; N = listen
    BEQ     FLY_S1_HBACK
    BRA     FLY_S1_HWAIT         ; Other key -> ask again

FLY_S1_DISOBEY:
    MOVE.W  #1,DISOBEYED         ; Mark that player disobeyed
    BRA     FLY_S1_DO_SEP

FLY_S1_HBACK:
    ; Erase warning and go back to flying
    MOVE.W  #$0015,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  #$0016,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    BRA     FLY_S1_DELAY

; --- Actually separate stage 1 ---
FLY_S1_DO_SEP:
    BSR     ERASE_FIRST_SEP      ; Erase the upper-stage rocket

    ; Erase prompt/warning rows (20-22)
    MOVE.W  #$0014,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  #$0015,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  #$0016,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15

    ; Move to sub-stage 2 (coasting phase)
    MOVE.W  #2,STAGE_SEP
    MOVE.W  #STAGE2_FUEL,FLY_FUEL ; Fill up coasting fuel

    ; Draw the even smaller capsule-only rocket
    BSR     DRAW_STARS
    BSR     DRAW_SECOND_SEP

; --- Frame delay for stage 1 ---
FLY_S1_DELAY:
    BSR     SHOW_FLY_STATS       ; Update stats
    MOVE.L  #4,D1                ; 4ms delay
    MOVE.B  #23,D0
    TRAP    #15
    BRA     DO_FLY               ; Loop back

    ; ======= STAGE 2: Coasting to orbit =======
    ; The rocket is now just the capsule, coasting upward.
    ; If the player disobeyed Houston earlier, a timer is
    ; counting down. If it runs out, the mission fails.
    ; Otherwise, keep climbing until altitude reaches 320.
FLY_STAGE2:
    ; Check if player disobeyed Houston earlier
    TST.W   DISOBEYED
    BEQ     FLY_S2_OK            ; Didn't disobey -> all good

    ADDQ.W  #1,COAST_CTR         ; Count frames since disobeying
    MOVE.W  COAST_CTR,D0
    CMP.W   #60,D0               ; Has it been 60 frames?
    BGE     FLY_DISOBEY_FAIL     ; Yes -> mission fails (told you so!)

FLY_S2_OK:
    SUBQ.W  #1,FLY_FUEL          ; Burn coasting fuel
    MOVE.W  FLY_FUEL,D0
    BLE     FLY_S2_FUEL_OUT      ; Ran out of fuel -> fail

    ; Check if we've reached orbit altitude
    MOVE.W  ALT,D0
    CMP.W   #320,D0              ; Altitude >= 320?
    BGE     FLY_GO_DOCK          ; Yes! Move to docking phase

    BSR     SHOW_FLY_STATS       ; Update stats display
    MOVE.L  #4,D1                ; 4ms delay
    MOVE.B  #23,D0
    TRAP    #15
    BRA     DO_FLY               ; Keep flying

; --- Reached orbit! Transition to docking phase ---
FLY_GO_DOCK:
    BSR     ERASE_SECOND_SEP     ; Erase the capsule rocket
    BSR     CLEAR_SCREEN         ; Clean slate
    CLR.W   FLY_INIT             ; Reset init flag for if we come back
    CLR.W   STAGE_SEP            ; Reset sub-stage

    ; Play the docking briefing page sound
    LEA     SND_DOCKPAGE,A1
    BSR     PLAY_WAV

    ; Show Phase 2 instruction screen (explains docking)
    LEA     SCR_PHASE2,A2
    BSR     PHASE_SCREEN

    MOVE.B  #DOCK_STATE,STATE    ; Switch to docking phase
    BRA     MAIN_LOOP

; --- FAILURE: Ran out of fuel during stage 0 or 1 ---
FLY_FUEL_OUT:
    LEA     SND_PROBLEM,A1       ; Play failure sound
    BSR     PLAY_WAV
    BSR     CLEAR_SCREEN
    MOVE.W  #$050A,D1            ; Cursor: col=5, row=10
    MOVE.B  #11,D0
    TRAP    #15
    LEA     FLY_FUEL_MSG,A1      ; "OUT OF FUEL! MISSION FAILED"
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.B  #5,D0                ; Wait for any key
    TRAP    #15
    BRA     END_GAME

; --- FAILURE: Ran out of fuel during coasting (stage 2) ---
FLY_S2_FUEL_OUT:
    LEA     SND_PROBLEM,A1
    BSR     PLAY_WAV
    BSR     CLEAR_SCREEN
    MOVE.W  #$050A,D1            ; Cursor: col=5, row=10
    MOVE.B  #11,D0
    TRAP    #15
    LEA     S2_FUEL_MSG,A1       ; "OUT OF FUEL - ALTITUDE NOT REACHED!"
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.B  #5,D0
    TRAP    #15
    BRA     END_GAME

; --- FAILURE: Disobeyed Houston and paid the price ---
FLY_DISOBEY_FAIL:
    LEA     SND_PROBLEM,A1
    BSR     PLAY_WAV
    BSR     CLEAR_SCREEN
    MOVE.W  #$050A,D1            ; Cursor: col=5, row=10
    MOVE.B  #11,D0
    TRAP    #15
    LEA     DISOBEY_MSG,A1       ; "Insufficient altitude - Mission Failed"
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.B  #5,D0
    TRAP    #15
    BRA     END_GAME

*===========================================================
* PHASE 2: SPACE RENDEZVOUS (Docking)
* The CSM (Command & Service Module) needs to dock with
* the LM (Lunar Module). Player moves CSM using WASD keys.
* Press E when aligned to attempt docking.
* If CSM collides with LM -> crash (mission fails).
* If CSM is close enough when E is pressed -> success!
*===========================================================
DO_DOCK:
    BSR     CLEAR_SCREEN
    BSR     SHOW_STATS           ; Show altitude at bottom

    ; Draw the LM (it stays still - player moves CSM toward it)
    MOVE.W  LM_X,D4              ; LM column position
    MOVE.W  #LM_ROW,D3           ; LM row position (fixed at row 5)
    LEA     PTR_LM_UP,A0         ; LM sprite pointer table
    MOVE.W  #SPRITE_H,D2         ; Sprite is 5 rows tall
    BSR     DRAW_SPRITE

    ; Draw the CSM at its starting position
    MOVE.W  CSM_X,D4             ; CSM column
    MOVE.W  CSM_Y,D3             ; CSM row
    LEA     PTR_CSM,A0           ; CSM sprite pointer table
    MOVE.W  #SPRITE_H,D2
    BSR     DRAW_SPRITE

    ; Show docking controls at bottom of screen
    MOVE.W  #$1500,D1            ; Cursor: col=21, row=0
    MOVE.B  #11,D0
    TRAP    #15
    LEA     DOCK_MSG,A1          ; "Move: WASD Controls e=Dock"
    MOVE.B  #14,D0
    TRAP    #15

*-----------------------------------------------------------
* DOCK_LOOP - Main docking game loop
* Reads keys, moves CSM, checks for collision and docking.
*-----------------------------------------------------------
DOCK_LOOP:
    ; Check if a key is pressed (non-blocking)
    MOVE.B  #7,D0
    TRAP    #15
    TST.B   D1
    BEQ     DOCK_NO_KEY          ; No key -> just wait

    ; A key was pressed. Move cursor to a safe spot before reading,
    ; because Task 5 echoes the character to the screen.
    MOVE.W  #$0018,D1            ; Cursor: col=0, row=24 (off-screen area)
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.B  #5,D0                ; Task 5 = read key (echoes character)
    TRAP    #15                  ; D1.B now has the key
    MOVE.B  D1,D2                ; SAVE the key in D2 (D1 will be reused)

    ; Erase the echoed character so it doesn't show on screen
    MOVE.W  #$0018,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANK_SMALL,A1       ; Print spaces over the echo
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.B  D2,D1                ; RESTORE the key back to D1

    ; Save the CSM's current position (so we can erase it later)
    MOVE.W  CSM_X,OLD_CSM_X
    MOVE.W  CSM_Y,OLD_CSM_Y

    ; --- Check which key was pressed ---
    CMP.B   #'w',D1              ; W = move up
    BEQ     M_U
    CMP.B   #'W',D1
    BEQ     M_U
    CMP.B   #'s',D1              ; S = move down
    BEQ     M_S
    CMP.B   #'S',D1
    BEQ     M_S
    CMP.B   #'a',D1              ; A = move left
    BEQ     M_L
    CMP.B   #'A',D1
    BEQ     M_L
    CMP.B   #'d',D1              ; D = move right
    BEQ     M_R
    CMP.B   #'D',D1
    BEQ     M_R
    CMP.B   #'e',D1              ; E = attempt docking
    BEQ     M_D
    CMP.B   #'E',D1
    BEQ     M_D

; No valid key (or no key pressed) -> just delay and loop
DOCK_NO_KEY:
    MOVE.L  #8,D1                ; 8ms frame delay
    MOVE.B  #23,D0
    TRAP    #15
    BRA     DOCK_LOOP

; --- CSM movement handlers ---
M_L:                             ; Move CSM left
    SUBQ.W  #2,CSM_X
    BRA     DOCK_MOVED
M_R:                             ; Move CSM right
    ADDQ.W  #2,CSM_X
    BRA     DOCK_MOVED
M_U:                             ; Move CSM up
    SUBQ.W  #1,CSM_Y
    BRA     DOCK_MOVED
M_S:                             ; Move CSM down
    ADDQ.W  #1,CSM_Y
    BRA     DOCK_MOVED

; --- After CSM moved: check for collision ---
DOCK_MOVED:
    ; Collision detection using bounding box overlap.
    ; Two boxes overlap if NONE of these are true:
    ;   CSM is fully left of LM
    ;   CSM is fully right of LM
    ;   CSM is fully above LM
    ;   CSM is fully below LM

    ; Check: is CSM's right edge left of LM's left edge?
    MOVE.W  CSM_X,D0
    ADD.W   #5,D0                ; CSM right edge
    CMP.W   LM_X,D0
    BLE     DOCK_NO_COLL         ; Yes -> no overlap

    ; Check: is LM's right edge left of CSM's left edge?
    MOVE.W  LM_X,D0
    ADD.W   #4,D0                ; LM right edge
    CMP.W   CSM_X,D0
    BLE     DOCK_NO_COLL         ; Yes -> no overlap

    ; Check: is CSM's bottom above LM's top?
    MOVE.W  CSM_Y,D0
    ADD.W   #SPRITE_H-1,D0       ; CSM bottom edge
    CMP.W   #LM_ROW,D0
    BLE     DOCK_NO_COLL         ; Yes -> no overlap

    ; Check: is LM's bottom above CSM's top?
    MOVE.W  #LM_ROW,D0
    ADD.W   #SPRITE_H-1,D0       ; LM bottom edge
    CMP.W   CSM_Y,D0
    BLE     DOCK_NO_COLL         ; Yes -> no overlap

    ; If we get here, boxes overlap -> CRASH!
    BRA     DOCK_CRASH

DOCK_NO_COLL:
    ; No collision - safe to redraw
    BSR     ERASE_CSM            ; Erase CSM at old position

    ; Redraw the LM first (in case CSM erased part of it)
    MOVE.W  LM_X,D4
    MOVE.W  #LM_ROW,D3
    LEA     PTR_LM_UP,A0
    MOVE.W  #SPRITE_H,D2
    BSR     DRAW_SPRITE

    ; Draw CSM at new position (on top of everything)
    MOVE.W  CSM_X,D4
    MOVE.W  CSM_Y,D3
    LEA     PTR_CSM,A0
    MOVE.W  #SPRITE_H,D2
    BSR     DRAW_SPRITE
    BRA     DOCK_NO_KEY          ; Go to delay and loop

; --- E pressed: attempt docking ---
M_D:
    ; Check if CSM is close enough horizontally to LM
    MOVE.W  CSM_X,D0
    SUB.W   LM_X,D0              ; Difference in X
    BSR     ABS                  ; Make it positive
    CMP.W   #4,D0                ; Within 4 columns?
    BGT     DOCK_LOOP            ; Too far -> ignore

    ; Check if CSM is close enough vertically (right below LM)
    MOVE.W  CSM_Y,D0
    SUB.W   #LM_ROW+5,D0         ; Distance from bottom of LM
    BSR     ABS
    CMP.W   #2,D0                ; Within 2 rows?
    BGT     DOCK_LOOP            ; Too far -> ignore
    ; *** DOCKING SUCCESSFUL! ***
D_OK:
    ; Play the docking success sound
    LEA     SND_DOCK,A1
    BSR     PLAY_WAV

    ; Erase the controls text from the screen
    MOVE.W  #$1500,D1            ; Same position as DOCK_MSG
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15

    ; Show "DOCKING SUCCESSFUL!" message on screen
    MOVE.W  #$1A10,D1            ; Cursor: col=26, row=16
    MOVE.B  #11,D0
    TRAP    #15
    LEA     DOCK_OK_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15

    ; Show "Press W to proceed" below the success message
    MOVE.W  #$1912,D1            ; Cursor: col=25, row=18
    MOVE.B  #11,D0
    TRAP    #15
    LEA     DOCK_PRESS_W,A1
    MOVE.B  #14,D0
    TRAP    #15

    ; --- Wait for player to press W before continuing ---
DOCK_WAIT_W:
    MOVE.B  #7,D0                ; Non-blocking key check
    TRAP    #15
    TST.B   D1
    BEQ     DOCK_WAIT_W          ; No key -> keep waiting

    ; Read the key at a safe cursor position (to hide the echo)
    MOVE.W  #$0018,D1            ; Move cursor off-screen
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.B  #5,D0                ; Read key
    TRAP    #15
    MOVE.B  D1,D2                ; Save key to D2

    ; Erase the echoed character
    MOVE.W  #$0018,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANK_SMALL,A1
    MOVE.B  #14,D0
    TRAP    #15

    CMP.B   #'w',D2              ; Was it W?
    BEQ     DOCK_GO_FLY          ; Yes -> proceed!
    CMP.B   #'W',D2
    BEQ     DOCK_GO_FLY
    BRA     DOCK_WAIT_W          ; Other key -> keep waiting

; --- Clean up docking screen and move to trans-lunar phase ---
DOCK_GO_FLY:
    ; Erase "Docking Successful!" text
    MOVE.W  #$1A10,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15

    ; Erase "Press W to proceed" text
    MOVE.W  #$1912,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15

    ; Erase the CSM sprite at its current position
    MOVE.W  CSM_X,OLD_CSM_X
    MOVE.W  CSM_Y,OLD_CSM_Y
    BSR     ERASE_CSM
    
    ; Erase the LM sprite at its fixed position
    MOVEM.L D0-D5/A0-A1,-(A7)   ; Save registers on the stack
    MOVE.W  LM_X,D4              ; LM column
    MOVE.W  #LM_ROW,D3           ; LM row
    MOVE.W  #SPRITE_H,D2         ; Sprite height
    
; Loop to blank out each row of the LM
ERASE_LM_DOCK
    MOVE.W  D4,D1                ; Column
    LSL.W   #8,D1                ; Shift to upper byte
    OR.B    D3,D1                ; Add row
    MOVE.B  #11,D0               ; Set cursor
    TRAP    #15
    LEA     BLANK_SMALL,A1       ; Print blanks
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3                ; Next row
    SUBQ.W  #1,D2                ; One less to do
    BNE     ERASE_LM_DOCK        ; Keep going
    MOVEM.L (A7)+,D0-D5/A0-A1   ; Restore registers from stack
    
    BSR     CLEAR_SCREEN
    CLR.W   DOCKED_ALT           ; Reset altitude counter for next phase

    ; Show Phase 3 transition screen
    LEA     SND_TRANSPAGE,A1     ; Play trans-lunar briefing sound
    BSR     PLAY_WAV
    LEA     SCR_PHASE3,A2        ; Load Phase 3 screen
    BSR     PHASE_SCREEN         ; Display it

    MOVE.B  #FLY_DOCKED,STATE    ; Switch to trans-lunar flight
    BRA     MAIN_LOOP

; --- CRASH: CSM collided with LM ---
DOCK_CRASH:    
    LEA     SND_PROBLEM,A1       ; Play failure sound
    BSR     PLAY_WAV
    BSR     CLEAR_SCREEN
    MOVE.W  #$050A,D1            ; Cursor: col=5, row=10
    MOVE.B  #11,D0
    TRAP    #15
    LEA     HOUSTON_PROB,A1      ; "Houston, we had a problem!"
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.B  #5,D0                ; Wait for any key
    TRAP    #15
    BRA     END_GAME

*===========================================================
* PHASE 3: TRANS-LUNAR FLIGHT (Docked)
* The CSM+LM are docked together, flying toward the Moon.
* This phase is fully automatic - no player input needed.
* The craft just flies until altitude counter hits 50,
* then it transitions to the landing phase.
*===========================================================
DO_FLY_DOCKED:
    ; First frame only: clear screen and play sound
    TST.W   DOCKED_ALT           ; Is this the very first frame?
    BNE     DFD_SKIP_CLEAR       ; No -> skip setup
    BSR     CLEAR_SCREEN
    LEA     SND_TRANSLUNAR,A1    ; Play trans-lunar flight music
    BSR     PLAY_WAV

DFD_SKIP_CLEAR:
    ; Blank the hint row every frame (prevents stale text)
    MOVE.W  #$1500,D1            ; Row 21
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15

    BSR     SHOW_STATS           ; Update altitude display
    ADDQ.W  #1,ALT               ; Altitude keeps going up
    ADDQ.W  #1,DOCKED_ALT        ; Count how far toward Moon

    ; Animate: erase old craft, draw stars, draw craft at same spot
    BSR     ERASE_JOINT          ; Erase the docked craft
    BSR     DRAW_STARS           ; Redraw stars
    BSR     DRAW_JOINT           ; Draw the docked craft again

    ; Frame delay
    MOVE.L  #4,D1                ; 4ms
    MOVE.B  #23,D0
    TRAP    #15

    ; Check if we've reached the Moon (altitude counter >= 50)
    MOVE.W  DOCKED_ALT,D0
    CMP.W   #50,D0
    BGE     GO_LAND              ; Yes -> start landing!
    BRA     DO_FLY_DOCKED        ; No -> keep flying

; --- Reached the Moon! Transition to landing ---
GO_LAND:
    BSR     CLEAR_SCREEN
    LEA     SCR_PHASE4,A2        ; Show Phase 4 instruction screen
    BSR     PHASE_SCREEN
    MOVE.B  #LAND_STAGE,STATE    ; Switch to landing phase
    BRA     MAIN_LOOP

*-----------------------------------------------------------
* DRAW_JOINT - Draws the docked CSM+LM craft together
* LM on top (row 5), CSM below it (row 9), at column 34
*-----------------------------------------------------------
DRAW_JOINT:
    MOVEM.L D0-D5/A0-A1,-(A7)   ; Save registers
    MOVE.W  #34,D4               ; Column 34
    MOVE.W  #5,D3                ; LM starts at row 5
    LEA     PTR_LM_UP,A0         ; LM sprite
    MOVE.W  #5,D2                ; 5 rows
    BSR     DRAW_SPRITE
    MOVE.W  #9,D3                ; CSM starts at row 9 (right below LM)
    LEA     PTR_CSM_FLY,A0       ; CSM sprite (with exhaust)
    MOVE.W  #6,D2                ; 6 rows
    BSR     DRAW_SPRITE
    MOVEM.L (A7)+,D0-D5/A0-A1   ; Restore registers
    RTS

*-----------------------------------------------------------
* ERASE_JOINT - Erases the docked craft by printing blanks
* Covers rows 5-14 at column 34
*-----------------------------------------------------------
ERASE_JOINT:
    MOVEM.L D0-D5/A0-A1,-(A7)   ; Save registers
    MOVE.W  #34,D4               ; Column 34
    MOVE.W  #5,D3                ; Start row
    MOVE.W  #10,D2               ; 10 rows to erase (LM 5 + CSM 5)
EJ_L:
    MOVE.W  D4,D1                ; Build cursor position
    LSL.W   #8,D1                ; Column to upper byte
    OR.B    D3,D1                ; Row to lower byte
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANK_SMALL,A1       ; Print blanks
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3                ; Next row
    SUBQ.W  #1,D2                ; Decrement counter
    BNE     EJ_L                 ; Keep going until done
    MOVEM.L (A7)+,D0-D5/A0-A1   ; Restore registers
    RTS

*===========================================================
* PHASE 4: LUNAR LANDING
* Player controls LM descent onto the moon surface.
*   W = thrust upward (uses fuel)
*   A = move left
*   D = move right
* Gravity pulls the LM down every frame.
* Must land in the safe flat zone with speed <= 2.
* Too fast or wrong spot = crash!
*===========================================================
DO_LANDING:
    ; --- One-time setup (runs only the first time) ---
    TST.W   LANDING_INIT         ; Already initialized?
    BNE     SKIP_LANDING_INIT    ; Yes -> skip

    BSR     CLEAR_SCREEN
    LEA     SND_LANDING,A1       ; Play landing phase music
    BSR     PLAY_WAV
    BSR     DRAW_MOON_SURFACE    ; Draw the moon landscape (once)
    BSR     INIT_LMU_LANDING     ; Set up LM position and fuel
    MOVE.W  #1,LANDING_INIT      ; Mark as initialized

SKIP_LANDING_INIT:
    ; --- Main landing loop ---
    ; 1. Save current position (for erasing later)
    MOVE.W  LMU_X,OLD_LMU_X
    MOVE.W  LMU_Y,OLD_LMU_Y

    ; 2. Read player input (thrust/steer)
    BSR     READ_LANDING_INPUT

    ; 3. Erase old LM position, update physics, draw new position
    BSR     ERASE_LMU
    BSR     UPDATE_LMU           ; Apply gravity, velocity, position
    BSR     DRAW_LMU

    ; 4. Show stats (speed, fuel, position)
    BSR     SHOW_LANDING_STATS

    ; 5. Check if LM has touched the surface
    BSR     CHECK_LANDING

    ; 6. Pause for game speed control
    MOVE.L  #FRAME_DELAY,D1      ; 90ms between frames
    MOVE.B  #23,D0
    TRAP    #15

    BRA     DO_LANDING           ; Loop forever until landing/crash

*-----------------------------------------------------------
* READ_LANDING_INPUT
* Checks if player pressed W/A/D and adjusts velocity.
* W = thrust up (costs fuel), A = push left, D = push right
* Non-blocking: if no key is pressed, nothing happens.
*-----------------------------------------------------------
READ_LANDING_INPUT:
    MOVEM.L D0-D1,-(A7)         ; Save registers

    ; Check for key without waiting
    MOVE.B  #7,D0                ; Task 7 = non-blocking key check
    TRAP    #15
    TST.B   D1                   ; Was a key pressed?
    BEQ     LAND_DONE            ; No -> do nothing

    MOVE.B  #5,D0                ; Task 5 = read the key
    TRAP    #15                  ; D1.B = the key pressed

    ; Check which key
    CMP.B   #'w',D1
    BEQ     LAND_THRUST           ; W = thrust
    CMP.B   #'W',D1
    BEQ     LAND_THRUST
    CMP.B   #'a',D1
    BEQ     LAND_LEFT             ; A = go left
    CMP.B   #'A',D1
    BEQ     LAND_LEFT
    CMP.B   #'d',D1
    BEQ     LAND_RIGHT            ; D = go right
    CMP.B   #'D',D1
    BEQ     LAND_RIGHT
    BRA     LAND_DONE             ; Other key -> ignore

LAND_THRUST:
    MOVE.W  LAND_FUEL,D0         ; Check if we have fuel
    BEQ     LAND_DONE            ; No fuel left -> can't thrust
    SUBQ.W  #1,LAND_FUEL         ; Use one unit of fuel
    SUB.W   #3,LMU_VY            ; Push upward (reduce downward speed)
    BRA     LAND_DONE

LAND_LEFT:
    SUB.W   #2,LMU_VX            ; Push left
    CMP.W   #-4,LMU_VX           ; Don't go too fast left
    BGE     LAND_DONE
    MOVE.W  #-4,LMU_VX           ; Clamp to max left speed
    BRA     LAND_DONE

LAND_RIGHT:
    ADD.W   #2,LMU_VX            ; Push right
    CMP.W   #4,LMU_VX            ; Don't go too fast right
    BLE     LAND_DONE
    MOVE.W  #4,LMU_VX            ; Clamp to max right speed
    BRA     LAND_DONE

LAND_DONE:
    MOVEM.L (A7)+,D0-D1         ; Restore registers
    RTS

*-----------------------------------------------------------
* INIT_LMU_LANDING
* Sets up the Lunar Module for the landing attempt.
* Places it at starting position with zero velocity.
*-----------------------------------------------------------
INIT_LMU_LANDING:
    MOVE.W  #LMU_START_X,LMU_X       ; Start column (right side)
    MOVE.W  #LMU_START_Y,LMU_Y       ; Start row (near top)
    MOVE.W  #LMU_START_X,OLD_LMU_X   ; Old position = same (no erasing needed)
    MOVE.W  #LMU_START_Y,OLD_LMU_Y
    CLR.W   LMU_VX                    ; No horizontal speed
    CLR.W   LMU_VY                    ; No vertical speed
    MOVE.W  #LAND_FUEL_MAX,LAND_FUEL  ; Fill the landing fuel tank
    RTS

*-----------------------------------------------------------
* UPDATE_LMU
* Applies gravity and velocity to update the LM position.
* Gravity pulls down each frame. Terminal velocity is
* capped at 3 so the game stays playable. Horizontal
* velocity has friction (drifts back toward zero).
*-----------------------------------------------------------
UPDATE_LMU:
    MOVEM.L D0,-(A7)            ; Save D0

    ; --- Apply gravity: increase downward speed ---
    ADD.W   #GRAVITY,LMU_VY

    ; Cap falling speed at 3 (terminal velocity)
    MOVE.W  LMU_VY,D0
    CMP.W   #3,D0
    BLE     UL_NO_CLAMP_V        ; Speed <= 3? OK
    MOVE.W  #3,LMU_VY            ; Too fast -> clamp to 3
UL_NO_CLAMP_V:

    ; --- Move vertically ---
    MOVE.W  LMU_VY,D0
    ADD.W   D0,LMU_Y             ; Add vertical speed to Y position

    ; Don't let LM go above the screen (row 0)
    MOVE.W  LMU_Y,D0
    CMP.W   #0,D0
    BGE     UL_HORIZ             ; Position >= 0? OK
    CLR.W   LMU_Y                ; Clamp to top of screen
    CLR.W   LMU_VY               ; Stop upward momentum

UL_HORIZ:
    ; --- Move horizontally ---
    MOVE.W  LMU_VX,D0
    ADD.W   D0,LMU_X             ; Add horizontal speed to X position

    ; --- Friction: slow down horizontal drift each frame ---
    ; Nudge velocity back toward zero by 2 per frame
    TST.W   LMU_VX
    BEQ     UL_DONE              ; Already zero -> skip
    BPL     UL_VX_POS            ; Positive -> reduce
    ADDQ.W  #2,LMU_VX            ; Negative VX: add 2 (toward zero)
    BRA     UL_DONE
UL_VX_POS:
    SUBQ.W  #2,LMU_VX            ; Positive VX: subtract 2 (toward zero)

UL_DONE:
    MOVEM.L (A7)+,D0            ; Restore D0
    RTS
*-----------------------------------------------------------
* DRAW_MOON_SURFACE
* Draws the complete moon landing scene background:
*   - Space with stars (rows 3-26)
*   - Rocky surface top edge (row 28)
*   - Solid ground (rows 29-37)
*   - A few extra stars scattered around
* This only runs once at the start of the landing phase.
*-----------------------------------------------------------
DRAW_MOON_SURFACE:
    MOVEM.L D0-D4/A0-A1,-(A7)   ; Save registers

    ; Draw space background rows (rows 3 to 26)
    MOVE.W  #3,D3                ; Start at row 3
MS_SPACE_L:
    MOVE.W  #0,D4                ; Column 0
    MOVE.W  D4,D1
    LSL.W   #8,D1                ; Build cursor position
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     SPACE_LINE,A1        ; Print a line of spaces (empty space)
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3                ; Next row
    CMP.W   #27,D3               ; Done all space rows?
    BLT     MS_SPACE_L           ; No -> keep going

    ; Draw the bumpy surface edge at row 28
    MOVE.W  #28,D3
    MOVE.W  #0,D4
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     SURFACE_TOP,A1       ; Wavy terrain line: ~~~~\/\/\____...
    MOVE.B  #14,D0
    TRAP    #15

    ; Draw solid ground blocks (rows 29-37)
    MOVE.W  #29,D3
MS_GROUND_L:
    MOVE.W  #0,D4
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     GROUND_LINE,A1       ; Row of #### chars (solid ground)
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    CMP.W   #38,D3               ; Done all ground rows?
    BLT     MS_GROUND_L

    ; Add a few hand-placed stars for atmosphere
    MOVE.W  #$0308,D1            ; Star at col 3, row 8
    BSR     P_S
    MOVE.W  #$1503,D1            ; Star at col 21, row 3
    BSR     P_S
    MOVE.W  #$4A06,D1            ; Star at col 74, row 6
    BSR     P_S
    MOVE.W  #$300B,D1            ; Star at col 48, row 11
    BSR     P_S

    MOVEM.L (A7)+,D0-D4/A0-A1   ; Restore registers
    RTS
*-----------------------------------------------------------
* DRAW_LMU
* Draws the Lunar Module at its current position (LMU_X, LMU_Y)
* using the landing sprite (legs extended).
*-----------------------------------------------------------
DRAW_LMU:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  LMU_X,D4             ; Current column
    MOVE.W  LMU_Y,D3             ; Current row
    LEA     PTR_LM_LAND,A0       ; Landing LM sprite (with legs)
    MOVE.W  #LM_LAND_H,D2        ; 5 rows tall
    BSR     DRAW_SPRITE
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

*-----------------------------------------------------------
* ERASE_LMU
* Blanks out the LM at its OLD position (where it was last
* frame), so the screen doesn't show ghost images.
*-----------------------------------------------------------
ERASE_LMU:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  OLD_LMU_X,D4         ; Old column
    MOVE.W  OLD_LMU_Y,D3         ; Old row
    MOVE.W  #LM_LAND_H,D2        ; 5 rows to erase
ELU_L:
    MOVE.W  D4,D1                ; Build cursor position
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANK_SMALL,A1       ; Print blanks to erase
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3                ; Next row
    SUBQ.W  #1,D2                ; Decrement counter
    BNE     ELU_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

*-----------------------------------------------------------
* SHOW_LANDING_STATS
* Displays controls, vertical speed, X position, and fuel
* at the top of the screen during the landing phase.
*-----------------------------------------------------------
SHOW_LANDING_STATS:
    MOVEM.L D0-D1,-(A7)

    ; Row 0: Show control hints
    MOVE.W  #$0000,D1            ; Cursor: col=0, row=0
    MOVE.B  #11,D0
    TRAP    #15
    LEA     LAND_CTRL_MSG,A1     ; "W=Thrust  A=Left  D=Right"
    MOVE.B  #14,D0
    TRAP    #15

    ; Row 1: Show vertical speed (VY) and X position
    ; First blank the row to prevent old numbers showing
    MOVE.W  #$0001,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15

    MOVE.W  #$0001,D1            ; Reposition to row 1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     VY_MSG,A1            ; "VY:"
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  LMU_VY,D1            ; Print the VY number
    BSR     PRINT_WORD_DEC
    LEA     X_MSG,A1             ; "  X:"
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  LMU_X,D1             ; Print the X number
    BSR     PRINT_WORD_DEC

    ; Row 2: Show remaining fuel
    MOVE.W  #$0002,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1    ; Blank row first
    MOVE.B  #14,D0
    TRAP    #15

    MOVE.W  #$0002,D1            ; Reposition to row 2
    MOVE.B  #11,D0
    TRAP    #15
    LEA     FUEL_MSG,A1          ; "FUEL:"
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  LAND_FUEL,D1         ; Print fuel number
    BSR     PRINT_WORD_DEC

    MOVEM.L (A7)+,D0-D1
    RTS

*-----------------------------------------------------------
* CHECK_LANDING
* Called every frame during landing. Checks if the LM has
* reached the moon surface (row 29). If it has:
*   - Velocity <= 2 AND in landing zone -> SUCCESS!
*   - Otherwise -> CRASH!
*-----------------------------------------------------------
CHECK_LANDING:
    MOVEM.L D0-D1,-(A7)

    ; Calculate where the bottom of the LM is
    MOVE.W  LMU_Y,D0
    ADD.W   #LM_LAND_H,D0        ; Bottom edge = Y + sprite height
    
    CMP.W   #SURFACE_Y,D0        ; Has bottom reached the surface?
    BLT     CL_DONE              ; No -> still in the air, return

    ; LM has reached the surface! Clamp it so it doesn't go below
    MOVE.W  #SURFACE_Y,D0
    SUB.W   #LM_LAND_H,D0
    MOVE.W  D0,LMU_Y             ; Place LM right on the surface

    ; --- TOUCHDOWN! Now check if it was good ---

    ; Check speed: velocity must be 2 or less
    MOVE.W  LMU_VY,D1
    CMP.W   #2,D1
    BGT     CL_CRASH             ; Too fast! Crash.

    ; Check horizontal position: must be in the flat landing zone
    MOVE.W  LMU_X,D0

    ; Is LM too far left?
    CMP.W   #LANDING_ZONE_X1,D0
    BLT     CL_CRASH             ; Left of safe zone -> crash

    ; Is LM too far right? (account for LM width)
    MOVE.W  #LANDING_ZONE_X2,D1
    SUB.W   #LM_WIDTH,D1         ; Right boundary minus LM width
    CMP.W   D1,D0
    BGT     CL_CRASH             ; Right of safe zone -> crash

    ; *** SUCCESSFUL LANDING! ***
    MOVEM.L (A7)+, D0-D1         ; Restore registers
    LEA     SND_STEP,A1          ; Play "One small step" sound
    BSR     PLAY_WAV
    BSR     CLEAR_SCREEN
    MOVE.W  #$0809,D1            ; Cursor: col=8, row=9
    MOVE.B  #11,D0
    TRAP    #15
    LEA     LAND_SUCCESS,A1      ; "EAGLE HAS LANDED!"
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.B  #5,D0                ; Wait for any key
    TRAP    #15
    BRA     CL_END_GAME          ; End the game (you won!)

; --- CRASH LANDING ---
CL_CRASH:
    MOVEM.L (A7)+, D0-D1        ; Restore registers
    LEA     SND_PROBLEM,A1       ; Play failure sound
    BSR     PLAY_WAV
    BSR     CLEAR_SCREEN
    MOVE.W  #$0809,D1            ; Cursor: col=8, row=9
    MOVE.B  #11,D0
    TRAP    #15
    LEA     LAND_CRASH,A1        ; "CRASH LANDING! MISSION FAILED"
    MOVE.B  #14,D0
    TRAP    #15
    BRA     END_GAME

; Still in the air - just return
CL_DONE:
    MOVEM.L (A7)+,D0-D1
    RTS

; After successful landing, end the game
CL_END_GAME:
    BRA     END_GAME
*===========================================================
* RENDERING SUBROUTINES
* These routines draw and erase sprites on the text screen.
* "Drawing" means printing ASCII art characters at positions.
* "Erasing" means printing blank spaces over those positions.
*===========================================================

*-----------------------------------------------------------
* DRAW_LAUNCH_PAD
* Draws the launch tower/gantry next to the rocket.
* 32 rows tall, at column 53 (to the right of the rocket).
*-----------------------------------------------------------
DRAW_LAUNCH_PAD:
    LEA     PTR_LAUNCH_PAD,A0    ; Pointer table for gantry sprite
    MOVE.W  #32,D2               ; 32 rows
    MOVE.W  #5,D3                ; Start at row 5
    MOVE.W  #53,D4               ; Column 53 (rocket is at col 38)
    BSR     DRAW_SPRITE
    RTS

*-----------------------------------------------------------
* DRAW_PAD_ROCKET
* Draws the rocket on the launch pad (no flames).
* 32 rows tall, at column 38.
*-----------------------------------------------------------
DRAW_PAD_ROCKET:
    LEA     PTR_SAT_PAD,A0       ; Pointer table for pad rocket (no flames)
    MOVE.W  #32,D2               ; 32 rows
    MOVE.W  #5,D3                ; Start at row 5
    MOVE.W  #38,D4               ; Column 38
    BSR     DRAW_SPRITE
    RTS

*-----------------------------------------------------------
* DRAW_FULL_ROCKET
* Draws the full Saturn V with exhaust flames.
* 33 rows tall, at column 38, starting row 1.
*-----------------------------------------------------------
DRAW_FULL_ROCKET:
    LEA     PTR_SATURN,A0        ; Full rocket + flames
    MOVE.W  #33,D2               ; 33 rows (rocket + flame rows)
    MOVE.W  #1,D3                ; Start at row 1
    MOVE.W  #38,D4               ; Column 38
    BSR     DRAW_SPRITE
    RTS

*-----------------------------------------------------------
* DRAW_FIRST_SEP
* Draws the upper stage after first separation.
* (Bottom booster dropped off, only upper stages remain)
*-----------------------------------------------------------
DRAW_FIRST_SEP:
    LEA     PTR_FIRST_SEP,A0     ; Upper stage sprite
    MOVE.W  #18,D2               ; 18 rows
    MOVE.W  #1,D3                ; Start at row 1
    MOVE.W  #38,D4               ; Column 38
    BSR     DRAW_SPRITE
    RTS

*-----------------------------------------------------------
* DRAW_SECOND_SEP
* Draws the capsule after second separation.
* (Only the CSM capsule + small engine remain)
*-----------------------------------------------------------
DRAW_SECOND_SEP:
    LEA     PTR_SECOND_SEP,A0    ; Capsule sprite
    MOVE.W  #14,D2               ; 14 rows
    MOVE.W  #1,D3                ; Start at row 1
    MOVE.W  #38,D4               ; Column 38
    BSR     DRAW_SPRITE
    RTS

*-----------------------------------------------------------
* DRAW_SPRITE - General-purpose sprite drawing routine
* This is the core rendering function used by ALL sprites.
*
* Input:
*   D4 = column to draw at
*   D3 = starting row
*   D2 = number of rows to draw
*   A0 = pointer to a table of DC.L pointers, each pointing
*        to a null-terminated string (one row of the sprite)
*
* How it works:
*   For each row, it sets the cursor to (D4, D3),
*   reads the next string pointer from the table,
*   and prints that string. Then moves to the next row.
*-----------------------------------------------------------
DRAW_SPRITE:
    MOVEM.L D0-D5/A0-A1,-(A7)   ; Save all registers we'll use
DS_L:
    MOVE.W  D4,D1                ; Start with the column number
    LSL.W   #8,D1                ; Shift column into upper byte
    OR.B    D3,D1                ; Put row in lower byte
    MOVE.B  #11,D0               ; Task 11 = set cursor position
    TRAP    #15
    MOVE.L  (A0)+,A1             ; Get next string pointer from table
    MOVE.B  #14,D0               ; Task 14 = print string
    TRAP    #15
    ADDQ.W  #1,D3                ; Move to next row
    SUBQ.W  #1,D2                ; One less row to draw
    BNE     DS_L                 ; Not done? Keep going
    MOVEM.L (A7)+,D0-D5/A0-A1   ; Restore registers
    RTS

*-----------------------------------------------------------
* ERASE_ROCKET - Erases the full rocket sprite
* Prints blank spaces over 34 rows at column 38.
*-----------------------------------------------------------
ERASE_ROCKET:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  #38,D4               ; Column 38
    MOVE.W  #1,D3                ; Start at row 1
    MOVE.W  #34,D2               ; 34 rows to erase
    LEA     BLANK_ROCKET,A1      ; A line of blank spaces
ER_R:
    MOVE.W  D4,D1                ; Build cursor position
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.B  #14,D0               ; Print blanks at this row
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     ER_R
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

*-----------------------------------------------------------
* ERASE_FIRST_SEP - Erases the upper-stage rocket
* 19 rows at column 38.
*-----------------------------------------------------------
ERASE_FIRST_SEP:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  #38,D4
    MOVE.W  #1,D3
    MOVE.W  #19,D2
    LEA     BLANK_ROCKET,A1
ER_F_L:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     ER_F_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

*-----------------------------------------------------------
* ERASE_SECOND_SEP - Erases the capsule-only rocket
* 15 rows at column 38.
*-----------------------------------------------------------
ERASE_SECOND_SEP:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  #38,D4
    MOVE.W  #1,D3
    MOVE.W  #15,D2
    LEA     BLANK_ROCKET,A1
ER_S_L:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     ER_S_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

*-----------------------------------------------------------
* ERASE_CSM - Erases the CSM at its OLD position
* Used during docking phase to clear the CSM before redraw.
*-----------------------------------------------------------
ERASE_CSM:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  OLD_CSM_X,D4         ; Old column
    MOVE.W  OLD_CSM_Y,D3         ; Old row
    MOVE.W  #SPRITE_H,D2         ; 5 rows
    LEA     BLANK_SMALL,A1       ; Blank spaces
ER_CSM_L:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     ER_CSM_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

*-----------------------------------------------------------
* DRAW_STARS - Draws a few stars in the background
* Places '*' characters at fixed screen positions.
*-----------------------------------------------------------
DRAW_STARS:
    MOVE.W  #$0502,D1            ; Star at col=5, row=2
    BSR     P_S
    MOVE.W  #$350A,D1            ; Star at col=53, row=10
    BSR     P_S
    MOVE.W  #$2204,D1            ; Star at col=34, row=4
    BSR     P_S
    RTS

; Helper: print one star at cursor position D1
P_S:
    MOVE.B  #11,D0               ; Set cursor
    TRAP    #15
    LEA     STAR,A1              ; '*' character
    MOVE.B  #14,D0               ; Print it
    TRAP    #15
    RTS

*-----------------------------------------------------------
* CLEAR_SCREEN - Wipes the entire text display clean.
* Uses TRAP #15 Task 12.
*-----------------------------------------------------------
CLEAR_SCREEN:
    MOVE.B  #12,D0               ; Task 12 = clear screen
    TRAP    #15
    RTS

*-----------------------------------------------------------
* PLAY_WAV - Plays a WAV sound file.
* Input: A1 = pointer to null-terminated filename string
* Uses TRAP #15 Task 70 (Easy68K audio playback).
*-----------------------------------------------------------
PLAY_WAV:
    MOVEM.L D0-D1,-(A7)         ; Save registers
    MOVE.B  #70,D0               ; Task 70 = play WAV file
    TRAP    #15
    MOVEM.L (A7)+,D0-D1         ; Restore registers
    RTS

*-----------------------------------------------------------
* SHOW_FLY_STATS
* Displays altitude and fuel on row 0 during the flight
* phase (Phases 0 and 1). Blanks the row first to prevent
* old numbers from showing through.
*-----------------------------------------------------------
SHOW_FLY_STATS:
    MOVEM.L D0-D1,-(A7)

    ; Blank row 0 first
    MOVE.W  #$0000,D1            ; Cursor: col=0, row=0
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15

    ; Print "ALTITUDE: <number>"
    MOVE.W  #$0000,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     ALT_MSG,A1           ; "ALTITUDE: "
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  ALT,D1               ; Get current altitude
    BSR     PRINT_WORD_DEC       ; Print it as a decimal number

    ; Print "  FUEL: <number>" right after altitude
    LEA     FLY_FUEL_LBL,A1      ; "  FUEL:"
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  FLY_FUEL,D1          ; Get current fuel
    BSR     PRINT_WORD_DEC       ; Print it

    MOVEM.L (A7)+,D0-D1
    RTS

*-----------------------------------------------------------
* SHOW_STATS
* Displays altitude on row 20. Used during docking and
* trans-lunar phases where fuel isn't shown.
*-----------------------------------------------------------
SHOW_STATS:
    MOVEM.L D0-D1,-(A7)

    ; Blank row 20 first
    MOVE.W  #$0014,D1            ; Cursor: col=0, row=20
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15

    ; Print altitude on row 20
    MOVE.W  #$0014,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     ALT_MSG,A1           ; "ALTITUDE: "
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  ALT,D1
    BSR     PRINT_WORD_DEC

    MOVEM.L (A7)+,D0-D1
    RTS

*-----------------------------------------------------------
* ABS - Makes D0.W positive (absolute value)
* If D0 is negative, it flips the sign.
*-----------------------------------------------------------
ABS:
    TST.W   D0                   ; Is D0 negative?
    BPL     A_X                  ; No -> already positive
    NEG.W   D0                   ; Yes -> flip sign
A_X:
    RTS

*-----------------------------------------------------------
* PRINT_WORD_DEC
* Converts a 16-bit signed number in D1.W to decimal text
* and prints it at the current cursor position.
*
* How it works:
*   1. Builds the number string right-to-left in PWD_BUF
*   2. Handles negative numbers (prepends '-')
*   3. Extracts digits by dividing by 10 repeatedly
*   4. Prints the result using Task 14
*
* Input: D1.W = the number to print
* Modifies: D0-D4, A1 (all saved and restored)
*-----------------------------------------------------------
PRINT_WORD_DEC:
    MOVEM.L D0-D4/A1,-(A7)      ; Save registers

    ; Point A1 to the END of the buffer (we build right-to-left)
    LEA     PWD_BUF+7,A1
    MOVE.B  #0,(A1)              ; Put null terminator at the end

    ; Check if the number is negative
    MOVE.W  D1,D2                ; Copy number to D2
    CLR.B   D3                   ; D3 = 0 means positive
    TST.W   D2                   ; Is D2 negative?
    BPL     PWD_POS              ; No -> skip
    NEG.W   D2                   ; Make it positive for digit extraction
    MOVE.B  #1,D3                ; D3 = 1 means we need a '-' later

PWD_POS:
    ; Special case: if the number is zero, just write '0'
    CMP.W   #0,D2
    BNE     PWD_DIGITS           ; Not zero -> extract digits
    SUBQ.L  #1,A1               ; Move back one spot in buffer
    MOVE.B  #'0',(A1)           ; Write '0'
    BRA     PWD_SIGN             ; Jump to sign handling

PWD_DIGITS:
    ; --- Extract digits one at a time ---
    ; We divide by 10. The remainder is the rightmost digit.
    ; The quotient becomes the new number. Repeat until zero.
PWD_DIG_LOOP:
    CLR.L   D4                   ; Clear D4 (need full 32 bits for DIVU)
    MOVE.W  D2,D4                ; Put number in D4
    DIVU    #10,D4               ; Divide by 10: quotient in low word, remainder in high word
    MOVE.W  D4,D2                ; Save quotient (what's left)
    SWAP    D4                   ; Move remainder to low word
    ADD.B   #'0',D4              ; Convert remainder to ASCII digit
    SUBQ.L  #1,A1               ; Move back in buffer
    MOVE.B  D4,(A1)             ; Store the digit
    TST.W   D2                   ; Is quotient zero?
    BNE     PWD_DIG_LOOP         ; No -> more digits to extract

PWD_SIGN:
    ; If the number was negative, add a '-' at the front
    TST.B   D3                   ; Was it negative?
    BEQ     PWD_PRINT            ; No -> just print
    SUBQ.L  #1,A1               ; Move back one more spot
    MOVE.B  #'-',(A1)           ; Write minus sign

PWD_PRINT:
    ; A1 now points to the start of our number string
    MOVE.B  #14,D0               ; Task 14 = print string
    TRAP    #15
    MOVEM.L (A7)+,D0-D4/A1      ; Restore registers
    RTS

*-----------------------------------------------------------
* PHASE_SCREEN - Transition/Instruction Screen
* Shows a multi-line info screen between game phases.
* Each screen has an objective, controls, and tips.
* Player presses P to proceed or Q to quit.
*
* Input: A2 = pointer to a table of DC.L pointers.
*        Each entry points to a string to display.
*        Table ends with DC.L 0 (null terminator).
*
* How it works:
*   1. Clears screen
*   2. Loops through the pointer table, printing each
*      string on its own row starting at row 2, col 3
*   3. Shows "P - Proceed    Q - Quit" prompt below
*   4. Waits for P or Q key
*   5. Q -> ends the game
*   6. P -> erases all text row by row, then returns
*-----------------------------------------------------------
PHASE_SCREEN:
    MOVEM.L D0-D3/A1-A2,-(A7)   ; Save registers
    BSR     CLEAR_SCREEN

    MOVE.W  #2,D3                ; Start printing at row 2

    ; --- Print each line of the screen ---
PS_LINE_LOOP:
    MOVE.L  (A2)+,D0             ; Get next pointer from table
    BEQ     PS_LINES_DONE        ; 0 = end of table
    MOVE.L  D0,A1                ; Put string pointer in A1

    ; Set cursor to col 3, current row
    MOVE.W  #3,D1                ; Column 3
    LSL.W   #8,D1                ; Shift to upper byte
    OR.B    D3,D1                ; Add row to lower byte
    MOVE.B  #11,D0               ; Set cursor
    TRAP    #15
    MOVE.B  #14,D0               ; Print the string
    TRAP    #15
    ADDQ.W  #1,D3                ; Move to next row
    BRA     PS_LINE_LOOP         ; Process next line

PS_LINES_DONE:
    ; Show P/Q prompt 2 rows below the last line of text
    ADDQ.W  #2,D3
    MOVE.W  #20,D1               ; Column 20 (centered-ish)
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     PQ_PROMPT,A1         ; "P - Proceed    Q - Quit"
    MOVE.B  #14,D0
    TRAP    #15

    ; --- Wait for P or Q key ---
PS_WAIT_KEY:
    MOVE.B  #7,D0                ; Non-blocking key check
    TRAP    #15
    TST.B   D1
    BEQ     PS_WAIT_KEY          ; No key -> keep waiting

    ; Read key at a safe cursor position (hides the echo)
    MOVE.W  #$0018,D1            ; Off-screen cursor position
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.B  #5,D0                ; Read key
    TRAP    #15
    MOVE.B  D1,D2                ; Save key in D2

    ; Erase the echoed character
    MOVE.W  #$0018,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANK_SMALL,A1
    MOVE.B  #14,D0
    TRAP    #15

    ; Check which key was pressed
    CMP.B   #'p',D2
    BEQ     PS_PROCEED           ; P = proceed to next phase
    CMP.B   #'P',D2
    BEQ     PS_PROCEED
    CMP.B   #'q',D2
    BEQ     PS_QUIT              ; Q = quit the game
    CMP.B   #'Q',D2
    BEQ     PS_QUIT
    BRA     PS_WAIT_KEY          ; Other key -> ask again

PS_QUIT:
    MOVEM.L (A7)+,D0-D3/A1-A2   ; Restore registers
    BSR     CLEAR_SCREEN
    BRA     END_GAME             ; Jump to game over

PS_PROCEED:
    ; Erase all text by blanking rows 0-30 one by one
    ; (CLEAR_SCREEN alone wasn't reliable, so we do it manually)
    MOVE.W  #0,D3                ; Start at row 0
PS_ERASE_LOOP:
    MOVE.W  #0,D1                ; Column 0
    LSL.W   #8,D1                ; Shift to upper byte
    OR.B    D3,D1                ; Add row
    MOVE.B  #11,D0               ; Set cursor
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1    ; Print a full line of spaces
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3                ; Next row
    CMP.W   #31,D3               ; Done all rows 0-30?
    BLT     PS_ERASE_LOOP        ; No -> keep going

    MOVEM.L (A7)+,D0-D3/A1-A2   ; Restore registers
    RTS                          ; Return to caller

*-----------------------------------------------------------
* END_GAME - Stops the simulator.
* Task 9 halts the program completely.
*-----------------------------------------------------------
END_GAME:
    MOVE.B  #9,D0                ; Task 9 = halt simulator
    TRAP    #15

*===========================================================
* DATA SECTION
* All the text strings, screen layouts, sound file paths,
* and ASCII art sprite data used by the game.
*===========================================================

; --- UI Strings ---
STAR:           DC.B    '*',0                        ; Single star character
ALT_MSG:        DC.B    'ALTITUDE: ',0               ; Altitude label
PROMPT_LAUNCH:  DC.B    'W to Lift Off!',0           ; Launch prompt
DOCK_MSG:       DC.B    'Move: WASD Controls e=Dock',0 ; Docking controls
BLANKLINE_WIDE: DC.B    '                                                                          ',0  ; Wide blank line for erasing
VY_MSG:         DC.B    'VY:',0                      ; Vertical speed label
X_MSG:          DC.B    '  X:',0                     ; X position label
FUEL_MSG:       DC.B    'FUEL:',0                    ; Landing fuel label
FLY_FUEL_LBL:   DC.B    '  FUEL:',0                  ; Flight fuel label
SEP_MSG:        DC.B    'Press W to separate stage 1!   ',0  ; Stage 0 sep prompt
SEP2_MSG:       DC.B    'Press W to separate stage 2!   ',0  ; Stage 1 sep prompt

; --- Houston Warning Messages ---
HOUSTON_MSG:    DC.B    'Eagle its Houston, do not proceed with early separation!',0
HOUSTON_OPT:    DC.B    'y=Proceed  n=Keep Flying',0

; --- Failure / Success Messages ---
DISOBEY_MSG:    DC.B    'Insufficient altitude - Mission Failed',0
FLY_FUEL_MSG:   DC.B    '*** OUT OF FUEL! MISSION FAILED ***',0
S2_FUEL_MSG:    DC.B    '*** OUT OF FUEL - ALTITUDE NOT REACHED! ***',0
LAND_SUCCESS:   DC.B    '*** EAGLE HAS LANDED! ***',0
LAND_CRASH:     DC.B    '*** CRASH LANDING! MISSION FAILED ***',0
HOUSTON_PROB:   DC.B    'Houston, we had a problem!',0

; --- Blank Strings (for erasing sprites) ---
BLANK_ROCKET:   DC.B    '                ',0         ; Blanks rocket-width
BLANK_SMALL:    DC.B    '          ',0               ; Blanks sprite-width

; --- Landing and Docking UI ---
LAND_CTRL_MSG:  DC.B    'W=Thrust  A=Left  D=Right',0
DOCK_OK_MSG:    DC.B    '*** DOCKING SUCCESSFUL! ***',0
DOCK_PRESS_W:   DC.B    'Press W to proceed to flight',0

; --- Phase Screen Prompt ---
PQ_PROMPT:      DC.B    'P - Proceed    Q - Quit',0

*-----------------------------------------------------------
* WELCOME SCREEN DATA
* ASCII art logo and game overview shown at startup.
* Each WEL_ label is one line of text.
* SCR_WELCOME is the pointer table that PHASE_SCREEN reads.
*-----------------------------------------------------------
WEL_A1: DC.B '                        _ _         __   ___  _  __',0
WEL_A2: DC.B '      /\               | | |       / /  / _ \| |/ /',0
WEL_A3: DC.B '     /  \   _ __   ___ | | | ___  / /_ | (_) | '' / ',0
WEL_A4: DC.B '    / /\ \ | ''_ \ / _ \| | |/ _ \| ''_ \ > _ <|  <  ',0
WEL_A5: DC.B '   / ____ \| |_) | (_) | | | (_) | (_) | (_) | . \ ',0
WEL_A6: DC.B '  /_/    \_\ .__/ \___/|_|_|\___/ \___/ \___/|_|\_\',0
WEL_A7: DC.B '           | |',0
WEL_A8: DC.B '           |_|',0
WEL_B1: DC.B ' ',0
; Game info text
WEL_L1: DC.B '  Apollo Moon Landing Mission by Nazariy Buryak',0
WEL_L2: DC.B ' ',0
WEL_L3: DC.B '  Guide your Saturn V rocket from launch pad',0
WEL_L4: DC.B '  to lunar surface but do it in Assembly:',0
WEL_L5: DC.B ' ',0
WEL_L6: DC.B '    1. Orbital Ascent     - Reach orbit',0
WEL_L7: DC.B '    2. Space Rendezvous   - Dock with LM',0
WEL_L8: DC.B '    3. Trans-Lunar Flight - Fly to Moon',0
WEL_L9: DC.B '    4. Lunar Landing      - Land on Moon',0

; Pointer table for welcome screen (ends with 0)
SCR_WELCOME: DC.L WEL_A1,WEL_A2,WEL_A3,WEL_A4,WEL_A5,WEL_A6,WEL_A7,WEL_A8
             DC.L WEL_B1,WEL_L1,WEL_L2,WEL_L3,WEL_L4,WEL_L5
             DC.L WEL_L6,WEL_L7,WEL_L8,WEL_L9
             DC.L 0

*-----------------------------------------------------------
* PHASE 1 INSTRUCTION SCREEN: Orbital Ascent
*-----------------------------------------------------------
; ===== PHASE 1 SCREEN: Orbital Flight =====
PH1_T1: DC.B '=======================================',0
PH1_T2: DC.B '        ORBITAL ASCENT STAGE',0
PH1_T3: DC.B '=======================================',0
PH1_B1: DC.B ' ',0
PH1_L1: DC.B 'OBJECTIVE: Reach orbital altitude 320',0
PH1_L2: DC.B ' ',0
PH1_L3: DC.B 'CONTROLS:',0
PH1_L4: DC.B '  W - Separate rocket stages',0
PH1_L5: DC.B ' ',0
PH1_L6: DC.B 'HOW TO PASS:',0
PH1_L7: DC.B '  - Burn through stage 0 fuel',0
PH1_L8: DC.B '  - Separate and burn stage 1',0
PH1_L9: DC.B '  - Separate and coast to altitude 320',0
PH1_LA: DC.B ' ',0
PH1_LB: DC.B 'WHAT CAN FAIL YOU:',0
PH1_LC: DC.B '  - Running out of fuel before altitude',0
PH1_LD: DC.B '  - Ignoring Houston separation warning',0

SCR_PHASE1: DC.L PH1_T1,PH1_T2,PH1_T3,PH1_B1
            DC.L PH1_L1,PH1_L2,PH1_L3,PH1_L4,PH1_L5
            DC.L PH1_L6,PH1_L7,PH1_L8,PH1_L9,PH1_LA
            DC.L PH1_LB,PH1_LC,PH1_LD
            DC.L 0

; ===== PHASE 2 SCREEN: Space Rendezvous =====
PH2_T1: DC.B '=======================================',0
PH2_T2: DC.B '      SPACE RENDEZVOUS STAGE',0
PH2_T3: DC.B '=======================================',0
PH2_B1: DC.B ' ',0
PH2_L1: DC.B 'OBJECTIVE: Dock CSM with the LM',0
PH2_L2: DC.B ' ',0
PH2_L3: DC.B 'CONTROLS:',0
PH2_L4: DC.B '  W/A/S/D - Move CSM module',0
PH2_L5: DC.B '  E       - Attempt docking',0
PH2_L6: DC.B ' ',0
PH2_L7: DC.B 'HOW TO PASS:',0
PH2_L8: DC.B '  - Align CSM with LM (Kiss in Space)',0
PH2_L9: DC.B '  - Press E when aligned to dock',0
PH2_LA: DC.B ' ',0
PH2_LB: DC.B 'WHAT CAN FAIL YOU:',0
PH2_LC: DC.B '  - Colliding with the LM (crash!)',0
PH2_LD: DC.B '  - Pressing E when not aligned',0

SCR_PHASE2: DC.L PH2_T1,PH2_T2,PH2_T3,PH2_B1
            DC.L PH2_L1,PH2_L2,PH2_L3,PH2_L4,PH2_L5,PH2_L6
            DC.L PH2_L7,PH2_L8,PH2_L9,PH2_LA
            DC.L PH2_LB,PH2_LC,PH2_LD
            DC.L 0

; ===== PHASE 3 SCREEN: Trans-Lunar Flight =====
PH3_T1: DC.B '=======================================',0
PH3_T2: DC.B '      TRANS-LUNAR FLIGHT STAGE',0
PH3_T3: DC.B '=======================================',0
PH3_B1: DC.B ' ',0
PH3_L1: DC.B 'OBJECTIVE: Fly docked craft to the Moon',0
PH3_L2: DC.B ' ',0
PH3_L3: DC.B 'CONTROLS:',0
PH3_L4: DC.B '  Automatic - no input needed',0
PH3_L5: DC.B ' ',0
PH3_L6: DC.B 'HOW TO PASS:',0
PH3_L7: DC.B '  - Wait for altitude to reach target',0
PH3_L8: DC.B '  - Flight is fully automated',0
PH3_L9: DC.B ' ',0
PH3_LA: DC.B 'WHAT CAN FAIL YOU:',0
PH3_LB: DC.B '  - Nothing! Enjoy the ride.',0

SCR_PHASE3: DC.L PH3_T1,PH3_T2,PH3_T3,PH3_B1
            DC.L PH3_L1,PH3_L2,PH3_L3,PH3_L4,PH3_L5
            DC.L PH3_L6,PH3_L7,PH3_L8,PH3_L9
            DC.L PH3_LA,PH3_LB
            DC.L 0

; ===== PHASE 4 SCREEN: Lunar Landing =====
PH4_T1: DC.B '=======================================',0
PH4_T2: DC.B '        LUNAR LANDING STAGE',0
PH4_T3: DC.B '=======================================',0
PH4_B1: DC.B ' ',0
PH4_L1: DC.B 'OBJECTIVE: Land the LM on the Moon',0
PH4_L2: DC.B ' ',0
PH4_L3: DC.B 'CONTROLS:',0
PH4_L4: DC.B '  W - Thrust (slow descent)',0
PH4_L5: DC.B '  A - Move left',0
PH4_L6: DC.B '  D - Move right',0
PH4_L7: DC.B ' ',0
PH4_L8: DC.B 'HOW TO PASS:',0
PH4_L9: DC.B '  - Land on safe flat zone',0
PH4_LA: DC.B '  - Touch down with velocity =<2',0
PH4_LB: DC.B ' ',0
PH4_LC: DC.B 'WHAT CAN FAIL YOU:',0
PH4_LD: DC.B '  - Landing outside the safe zone',0
PH4_LE: DC.B '  - Coming down too fast (crash!)',0
PH4_LF: DC.B '  - Running out of landing fuel',0

SCR_PHASE4: DC.L PH4_T1,PH4_T2,PH4_T3,PH4_B1
            DC.L PH4_L1,PH4_L2,PH4_L3,PH4_L4,PH4_L5,PH4_L6,PH4_L7
            DC.L PH4_L8,PH4_L9,PH4_LA,PH4_LB
            DC.L PH4_LC,PH4_LD,PH4_LE,PH4_LF
            DC.L 0
; --- Moon Surface Art (for landing phase) ---
SPACE_LINE:  DC.B '                                                                                ',0  ; Empty space row
SURFACE_TOP: DC.B '~~~~\/\/\________________________________________/\/\/\/\/\/\/\/\/\/\/\/\/\/~~~~',0  ; Bumpy surface edge
GROUND_LINE: DC.B '################################################################################',0  ; Solid ground

; --- Sound File Paths ---
; Each sound is a .wav file in the same folder as the program
SND_ENTRY:    DC.B 'gameentry.wav',0           ; Played at game start
SND_SAYAGAIN: DC.B 'sayagain.wav',0            ; Houston warning sound
SND_LANDING:  DC.B 'landingphase.wav',0        ; Landing phase music
SND_STEP:     DC.B 'smallstep.wav',0           ; Successful landing!
SND_DOCK:     DC.B 'dockingsuccsesful.wav',0   ; Docking success sound
SND_PROBLEM:  DC.B 'heustonproblem.wav',0      ; Crash/failure sound
SND_IGNITION: DC.B 'ignitionsecstart.wav',0    ; Launch ignition sound
SND_TRANSLUNAR: DC.B 'translunar.wav',0        ; Trans-lunar flight music
SND_DOCKPAGE: DC.B 'dockingpage.wav',0         ; Docking briefing sound
SND_TRANSPAGE: DC.B 'translunarpage.wav',0     ; Trans-lunar briefing sound

*-----------------------------------------------------------
* SPRITE POINTER TABLES
* Each table is a list of DC.L pointers to string rows.
* DRAW_SPRITE reads these tables to know which strings
* to print for each row of the sprite.
*-----------------------------------------------------------

; Full Saturn V rocket with exhaust flames (33 rows: S1-S33)
PTR_SATURN:    DC.L S1,S2,S3,S4,S5,S6,S7,S8,S9,S10,S11,S12,S13,S14,S15,S16,S17,S18,S19,S20,S21,S22,S23,S24,S25,S26,S27,S28,S29,S30,S31,S32,S33

; Saturn V on the pad without flames (32 rows: S1-S32)
PTR_SAT_PAD:   DC.L S1,S2,S3,S4,S5,S6,S7,S8,S9,S10,S11,S12,S13,S14,S15,S16,S17,S18,S19,S20,S21,S22,S23,S24,S25,S26,S27,S28,S29,S30,S31,S32

; After first separation: upper stages + engine flames (18 rows)
PTR_FIRST_SEP: DC.L S2,S3,S4,S5,S6,S7,S8,S9,S10,S11,S12,S13,S14,S15,S16,S17,S32,S33

; After second separation: just the CSM capsule + small flames (14 rows)
PTR_SECOND_SEP: DC.L S2,S3,S4,S5,S6,S7,S8,S9,S10,S11,S12,S13,S34,S35

; CSM (Command & Service Module) - used during docking (5 rows)
PTR_CSM:     DC.L C1,C2,C3,C4,C5

; CSM with exhaust - used during trans-lunar flight (6 rows)
PTR_CSM_FLY: DC.L C1,C2,C3,C4,C5,C6

; LM (Lunar Module) facing up - used during docking (5 rows)
PTR_LM_UP:   DC.L U1,U2,U3,U4,U5

; LM with landing legs - used during landing (5 rows)
PTR_LM_LAND: DC.L L1,L2,L3,L4,L5

; Launch pad gantry/tower (32 rows)
PTR_LAUNCH_PAD: DC.L SG1,SG2,SG3,SG4,SG5,SG6,SG7,SG8,SG9,SG10,SG11,SG12,SG13,SG14,SG15,SG16,SG17,SG18,SG19,SG20,SG21,SG22,SG23,SG24,SG25,SG26,SG27,SG28,SG29,SG30,SG31,SG32

*-----------------------------------------------------------
* SATURN V ROCKET SPRITE
* S1-S31 = rocket body
* S32-S33 = main engine exhaust flames
* S34-S35 = small engine flames (for 2nd separation)
*-----------------------------------------------------------
S1:  DC.B '       |       ',0   ; Nose tip (Only for launch)
S2:  DC.B '       !       ',0   ; Launch escape tower
S3:  DC.B '      / \      ',0
S4:  DC.B '      [ ]      ',0
S5:  DC.B '     /   \     ',0
S6:  DC.B '     |   |     ',0
S7:  DC.B '     |   |     ',0 
S8:  DC.B '     |___|     ',0
S9:  DC.B '    /__|__\    ',0 
S10: DC.B '    |     |    ',0   ; Third stage body
S11: DC.B '    |     |    ',0
S12: DC.B '    |     |    ',0
S13: DC.B '    |_____|    ',0
S14: DC.B '   /       \   ',0   ; Second stage top
S15: DC.B '   |       |   ',0
S16: DC.B '   |_______|   ',0
S17: DC.B '   | |   | |   ',0   ;
S18: DC.B '   | |   | |   ',0   ; First stage top
S19: DC.B '   |_|   |_|   ',0
S20: DC.B '   |       |   ',0
S21: DC.B '   |       |   ',0
S22: DC.B '   |       |   ',0
S23: DC.B '   |       |   ',0
S24: DC.B '   |       |   ',0
S25: DC.B '   |_     _|   ',0
S26: DC.B '   | | U | |   ',0
S27: DC.B '   | | S | |   ',0
S28: DC.B '   | | A | |   ',0
S29: DC.B '   | |   | |   ',0
S30: DC.B '  /| |   | |\  ',0
S31: DC.B ' |_|_|___|_|_| ',0
S32: DC.B '    /\/|\/\    ',0   ; Main engine flames (top)
S33: DC.B '    VVVVVVV    ',0   ; Main engine flames (bottom)
S34: DC.B '      /|\      ',0   ; Small engine flames (2nd sep)
S35: DC.B '      VVV      ',0   ; Small engine flames (2nd sep)

*-----------------------------------------------------------
* LAUNCH PAD GANTRY SPRITE
* SG1-SG32 = 32 rows of tower structure with platforms
*-----------------------------------------------------------
SG1:  DC.B '#############  ',0
SG2:  DC.B '   ##########  ',0
SG3:  DC.B '   ##########  ',0
SG4:  DC.B '#############  ',0
SG5:  DC.B '   ##########  ',0
SG6:  DC.B '   ##########  ',0
SG7:  DC.B '#############  ',0
SG8:  DC.B '   ##########  ',0
SG9:  DC.B '   ##########  ',0
SG10: DC.B '   ##########  ',0
SG11: DC.B '   ##########  ',0
SG12: DC.B '   ##########  ',0
SG13: DC.B '   ##########  ',0
SG14: DC.B '   ##########  ',0
SG15: DC.B '   ##########  ',0
SG16: DC.B '   ##########  ',0
SG17: DC.B '#############  ',0
SG18: DC.B '   ##########  ',0
SG19: DC.B '   ##########  ',0
SG20: DC.B '   ##########  ',0
SG21: DC.B '   ##########  ',0
SG22: DC.B '   ##########  ',0
SG23: DC.B '   ##########  ',0
SG24: DC.B '   ##########  ',0
SG25: DC.B '   ##########  ',0
SG26: DC.B '   ##########  ',0
SG27: DC.B '   ##########  ',0
SG28: DC.B '   ##########  ',0
SG29: DC.B '   ##########  ',0
SG30: DC.B '   ##########  ',0
SG31: DC.B '   ##########  ',0
SG32: DC.B '   ##########  ',0

*-----------------------------------------------------------
* CSM (Command & Service Module) SPRITE
* C1-C5 = main CSM for docking phase
* C6 = exhaust (added during trans-lunar flight)
*-----------------------------------------------------------
C1: DC.B '   /\   ',0         ; Capsule tip
C2: DC.B '  /__\  ',0
C3: DC.B ' |+  +| ',0
C4: DC.B ' [____] ',0
C5: DC.B '  /__\  ',0
C6: DC.B '   VV   ',0

*-----------------------------------------------------------
* LM (Lunar Module) SPRITES
* U1-U5 = LM facing up (during docking + trans-lunar)
* L1-L5 = LM with landing legs extended (during landing)
*-----------------------------------------------------------
U1: DC.B ' \ __ / ',0
U2: DC.B ' _|__|_ ',0
U3: DC.B ' [    ] ',0
U4: DC.B '  \__/  ',0
U5: DC.B '   ''   ',0         ; Docking tip

L1: DC.B '   __   ',0
L2: DC.B '  /  \  ',0
L3: DC.B ' [____] ',0
L4: DC.B '  |__|  ',0
L5: DC.B ' / vv \ ',0

    END START

*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~4~
