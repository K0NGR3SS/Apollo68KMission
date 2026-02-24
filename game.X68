*-----------------------------------------------------------
* Title      : Apollo 11 Mission
* Written by : Nazariy Buryak
* Date       : 18/02/2025
* Description: Apollo 11 Mission
*-----------------------------------------------------------

    ORG $1000                 ; Program starts at address $1000

*--- CONSTANTS ---
PAD_STATE   EQU 0             ; Rocket on the launch pad
FLY_STATE   EQU 1             ; In mid-flight (ascent)
DOCK_STATE  EQU 2             ; Docking phase in orbit
LAND_STATE  EQU 3             ; Lunar landing phase

*-------------------------------------------------------
* VARIABLES
*-------------------------------------------------------
    ORG $4000                 ; Variable memory block starting at $4000
ALT:        DC.W    0         ; 16-bit altitude counter
STATE:      DC.B    0         ; Current game state
    DS.B    1                 ; Padding/alignment byte
CSM_X:      DC.W    10        ; Command/Service Module X position
LM_X:       DC.W    40        ; Lunar Module X position
LAND_Y:     DC.W    2         ; Lunar Module vertical position
LAND_VY:    DC.W    0         ; Vertical speed (velocity) for landing

*-------------------------------------------------------
* START
*-------------------------------------------------------
    ORG $1000                 ; Reaffirm start of program area
START:
    BSR     CLEAR_SCREEN      ; Clear the display before starting

MAIN_LOOP:
    MOVE.B  STATE,D0          ; Load current state into D0
    CMP.B   #PAD_STATE,D0     ; Compare with PAD phase
    BEQ     DO_PAD
    CMP.B   #FLY_STATE,D0     ; Compare with FLIGHT phase
    BEQ     DO_FLY
    CMP.B   #DOCK_STATE,D0    ; Compare with DOCKING phase
    BEQ     DO_DOCK
    CMP.B   #LAND_STATE,D0    ; Compare with LANDING phase
    BEQ     DO_LAND
    BRA     END_GAME          ; Unknown state = end program

*-------------------------------------------------------
* PHASE 0: PRE-LAUNCH SEQUENCE
*-------------------------------------------------------
DO_PAD:
    BSR     DRAW_STARS        ; Draw stars background (static backdrop)
    MOVE.W  #5,D3             ; Y position for rocket (Row 5)
    BSR     DRAW_FULL_ROCKET  ; Draw the full Saturn V rocket sprite
    
    MOVE.W  #$1402,D1         ; Cursor position: row 20, column 2
    MOVE.B  #11,D0
    TRAP    #15               ; OS display command to position cursor
    
    LEA     PROMPT_LAUNCH,A1  ; Load "1 + ENTER TO LAUNCH!" message
    MOVE.B  #14,D0
    TRAP    #15               ; Display message
    
    MOVE.B  #18,D0            ; Input trap: wait for keyboard input
    TRAP    #15
    MOVE.B  #1,STATE          ; Switch game state to FLIGHT
    BRA     MAIN_LOOP         

*-------------------------------------------------------
* PHASE 1: FLIGHT
*-------------------------------------------------------
DO_FLY:
    BSR     CLEAR_SCREEN
    ADDQ.W  #1,ALT            ; Increase altitude each frame
    
    MOVE.W  #5,D3             ; Keep rocket visible near top of screen
    MOVE.W  ALT,D0
    CMP.W   #45,D0
    BGT     FLY_SEP           ; Once altitude >45, stage separation occurs
    BSR     DRAW_FULL_ROCKET
    BRA     FLY_STARS
FLY_SEP:
    BSR     DRAW_UPPER_STAGE  ; Draw upper stage only

FLY_STARS:
    BSR     DRAW_STARS        ; Background animation
    BSR     SHOW_STATS        ; Display altitude readout
    
    MOVE.L  #4,D1
    MOVE.B  #23,D0
    TRAP    #15               ; Wait or delay (simulate time passing)
    
    MOVE.W  ALT,D0
    CMP.W   #80,D0            ; Orbit achieved at altitude >= 80
    BGE     GO_DOCK
    BRA     DO_FLY

GO_DOCK:
    MOVE.B  #2,STATE          ; Switch to docking state
    BRA     MAIN_LOOP

*-------------------------------------------------------
* PHASE 2: DOCKING
*-------------------------------------------------------
DO_DOCK:
    BSR     CLEAR_SCREEN
    LEA     DOCK_MSG,A1       ; "DOCK: 1=L, 2=R, 3=DOCK"
    BSR     PRINT_STATUS_LINE  ; Show docking status prompt
    
    ; Draw Command Module (player controls)
    MOVE.W  CSM_X,D4
    MOVE.W  #8,D3
    LEA     PTR_CSM,A0
    MOVE.W  #5,D2
    BSR     DRAW_SPRITE
    
    ; Draw Lunar Module (target)
    MOVE.W  LM_X,D4
    MOVE.W  #8,D3
    LEA     PTR_LM,A0
    MOVE.W  #5,D2
    BSR     DRAW_SPRITE
    
    MOVE.B  #18,D0            ; Wait for keyboard input
    TRAP    #15
    CMP.L   #1,D1
    BEQ     M_L               ; Move left
    CMP.L   #2,D1
    BEQ     M_R               ; Move right
    CMP.L   #3,D1
    BEQ     M_D               ; Attempt docking
    BRA     DO_DOCK
    
M_L:
    BSR ERASE_CSM            ; Remove the old sprite
    SUBQ.W #5,CSM_X          ; Update X Position (Move Left)
    BRA DO_DOCK
M_R:
    BSR ERASE_CSM            ; Remove the old sprite
    ADDQ.W #5,CSM_X          ; Update X Position (Move Right)
    BRA DO_DOCK
M_D:
    MOVE.W  CSM_X,D0
    SUB.W   LM_X,D0
    BSR     ABS               ; Difference in X (distance)
    CMP.W   #5,D0             ; If within 5 pixels, it's aligned
    BLE     D_OK
    BRA     DO_DOCK
D_OK:
    CLR.W LAND_VY             ; Reset LAND_VY and LAND_Y before entering landing state
    MOVE.W  #2,LAND_Y
    MOVE.B  #3,STATE          ; Proceed to landing phase
    BRA     MAIN_LOOP

*-------------------------------------------------------
* PHASE 3: LUNAR LANDING
*-------------------------------------------------------
DO_LAND:
    BSR     CLEAR_SCREEN
    ADDQ.W  #1,LAND_VY        ; Apply gravity acceleration
    MOVE.W  LAND_VY,D0
    ADD.W   D0,LAND_Y         ; Update Y position based on velocity
    
    ; Draw lunar surface
    MOVE.W  #$1600,D1         ; Row 22 (near bottom)
    MOVE.B  #11,D0
    TRAP    #15
    LEA     SURFACE,A1
    MOVE.B  #14,D0
    TRAP    #15

    MOVE.W  #25,D4            ; LM X center
    MOVE.W  LAND_Y,D3         ; LM Y position
    LEA     PTR_LM,A0
    MOVE.W  #5,D2
    BSR     DRAW_SPRITE

    CMP.W   #18,LAND_Y        ; Touchdown detection
    BGE     L_HIT

    LEA     LAND_KEYS,A1
    BSR     PRINT_INPUT_LINE
    MOVE.B  #18,D0
    TRAP    #15               ; Read key input
    CMP.L   #1,D1
    BEQ     L_UP
    BRA     DO_LAND
L_UP:
    SUBI.W #4,LAND_VY         ; Reduce velocity = thrust upward
    BRA     DO_LAND

L_HIT:
    CMP.W   #4,LAND_VY        ; If impact speed <=4, safe landing
    BLE     WIN
    LEA     CRASH_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15               ; Display CRASH message
    BRA     END_GAME
WIN:
    LEA     WIN_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15
    BRA     END_GAME

*-------------------------------------------------------
* RENDERING AND DRAWING SUBROUTINES
*-------------------------------------------------------
DRAW_FULL_ROCKET:
    LEA     PTR_SATURN,A0
    MOVE.W  #15,D2            ; Rocket height is 15 lines
    MOVE.W  #35,D4            ; Column is 35
    BSR     DRAW_SPRITE
    RTS

DRAW_UPPER_STAGE:
    LEA     PTR_UPPER,A0
    MOVE.W  #8,D2             ; Shorter sprite height
    MOVE.W  #35,D4
    BSR     DRAW_SPRITE
    RTS

DRAW_SPRITE:
    MOVEM.L D0-D5/A0-A1,-(A7) ; Save registers
DS_L:
    MOVE.W  D4,D1
    LSL.W   #8,D1             ; Combine row and column into a word
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15               ; Set cursor position
    MOVE.L  (A0)+,A1          ; Load next line of sprite text
    MOVE.B  #14,D0
    TRAP    #15               ; Draw the string
    ADDQ.W  #1,D3             ; Move to next line down
    SUBQ.W  #1,D2
    BNE     DS_L              ; Loop until all lines drawn
    MOVEM.L (A7)+,D0-D5/A0-A1 ; Restore registers
    RTS

ERASE_CSM:
    MOVEM.L D0-D5/A0-A1,-(A7) ; Preserve registers because we modify them
    MOVE.W  CSM_X,D4          ; Load current X coordinate
    MOVE.W  #8,D3             ; Y is row position of the sprite on screen
    MOVE.W  #5,D2             ; sprite height

ER_L:                         ; Label to start erase loop
    MOVE.W  D4,D1
    LSL.W   #8,D1             ; Shift left 8 bites
    OR.B    D3,D1             ; Merge Y into low byte (full screen position)
    MOVE.B  #11,D0
    TRAP    #15               ; Set cursor at D1 position

    LEA     BLANKLINE,A1      ; Load address of the blank line text
    MOVE.B  #14,D0
    TRAP    #15               ; Print the blank string

    ADDQ.W  #1,D3             ; Move down one row each loop
    SUBQ.W  #1,D2             ; Decrease line counter
    BNE     ER_L              ; Loop until all lines of ship cleared

    MOVEM.L (A7)+,D0-D5/A0-A1 ; Restore preserved registers
    RTS

BLANKLINE: DC.B '       ',0   ; 7 blank spaces (same width as CSM sprite)

DRAW_STARS:
    MOVE.W  #$0502,D1
    BSR     P_S
    MOVE.W  #$350A,D1
    BSR     P_S
    RTS
P_S:
    MOVE.B #11,D0
    TRAP #15                  ; Set cursor
    LEA STAR,A1
    MOVE.B #14,D0
    TRAP #15                  ; Display "*"
    RTS

CLEAR_SCREEN:
    MOVE.B  #12,D0
    TRAP    #15               ; Clear terminal screen
    RTS

SHOW_STATS:
    MOVE.W  #$0014,D1         ; Cursor position: row 0, col 20
    MOVE.B  #11,D0
    TRAP    #15
    LEA     ALT_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15               ; Print "ALTITUDE: "
    MOVE.W  ALT,D1
    EXT.L   D1
    MOVE.B  #3,D0
    TRAP    #15               ; Print the value of ALT
    RTS

PRINT_STATUS_LINE:
    MOVE.W #$0000,D1
    MOVE.B #11,D0
    TRAP #15
    MOVE.B #14,D0
    TRAP #15
    RTS

PRINT_INPUT_LINE:
    MOVE.W #$0018,D1
    MOVE.B #11,D0
    TRAP #15
    MOVE.B #14,D0
    TRAP #15
    RTS

ABS:
    TST.W D0
    BPL A_X                   ; If positive, skip negate
    NEG.W D0
A_X: RTS

END_GAME:
    MOVE.B  #9,D0
    TRAP    #15               ; End simulation

*-------------------------------------------------------
* DATA STRINGS & SPRITE DEFINITIONS
*-------------------------------------------------------
STAR:       DC.B    '*',0
ALT_MSG:    DC.B    'ALTITUDE: ',0
PROMPT_LAUNCH: DC.B '1 + ENTER TO LAUNCH!',0
DOCK_MSG:   DC.B    'DOCK: 1=L, 2=R, 3=DOCK',0
LAND_KEYS:  DC.B    '1=THRUST: ',0
WIN_MSG:    DC.B    13,10,'SUCCESS!',0
CRASH_MSG:  DC.B    13,10,'CRASH!',0
SURFACE:    DC.B    '________________________________________________',0

PTR_SATURN: DC.L S1,S2,S3,S4,S5,S6,S7,S8,S9,S10,S11,S12,S13,S14,S15
PTR_UPPER:  DC.L S1,S2,S3,S4,S5,S6,S14,S15
PTR_CSM:    DC.L C1,C2,C3,C4,C5
PTR_LM:     DC.L L1,L2,L3,L4,L5

S1:  DC.B '     ^     ',0
S2:  DC.B '    / \    ',0
S3:  DC.B '   |   |   ',0
S4:  DC.B '   |   |   ',0
S5:  DC.B '   |   |   ',0
S6:  DC.B '   |---|   ',0
S7:  DC.B '   |   |   ',0
S8:  DC.B '   |   |   ',0
S9:  DC.B '   |---|   ',0
S10: DC.B '  /|   |\  ',0
S11: DC.B ' | |USA| | ',0
S12: DC.B ' |_|   |_| ',0
S13: DC.B '   |___|   ',0
S14: DC.B '    / \    ',0
S15: DC.B '   V V V   ',0

C1: DC.B '   /\   ',0
C2: DC.B '  /  \  ',0
C3: DC.B ' |    | ',0
C4: DC.B ' |____| ',0
C5: DC.B '  /__\  ',0

L1: DC.B '   __   ',0
L2: DC.B '  /  \  ',0
L3: DC.B ' [____] ',0
L4: DC.B '  |__|  ',0
L5: DC.B ' /    \ ',0

    END START