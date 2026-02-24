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
FLY_TLI     EQU 4             ; Trans Lunar Injection
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
DOCKED      DC.B    0

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
    CMP.B   #FLY_TLI, D0
    BEQ     DO_FLY_TLI
    CMP.B   #LAND_STATE,D0    ; Compare with LANDING phase
    BEQ     DO_LAND
    BRA     END_GAME          ; Unknown state = end program

*-------------------------------------------------------
* PHASE 0: PRE-LAUNCH SEQUENCE
*-------------------------------------------------------
DO_PAD:
    BSR     CLEAR_SCREEN      ; Wipe everything
    BSR     SHOW_STATS        ; Redraw altitude HUD

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
    BSR     ERASE_PROMPT      ; Erase text on screen fromm this state
    BRA     MAIN_LOOP         

*-------------------------------------------------------
* PHASE 1: FLIGHT
*-------------------------------------------------------
DO_FLY:
    BSR     SHOW_STATS        ; Update altitude number only

    ADDQ.W  #1,ALT            ; Increase altitude each frame
    
    BSR     ERASE_ROCKET      ; Clear old rocket
    BSR     DRAW_STARS        ; Background
    
    MOVE.W  #5,D3             ; Keep rocket visible near top
    MOVE.W  ALT,D0
    CMP.W   #45,D0
    BGT     FLY_SEP
    BSR     DRAW_FULL_ROCKET  ; Redraw at same position
    BRA     FLY_STARS

FLY_SEP:
    BSR     ERASE_ROCKET
    BSR     DRAW_UPPER_STAGE

FLY_STARS:
    MOVE.L  #4,D1
    MOVE.B  #23,D0
    TRAP    #15               ; Delay
    
    MOVE.W  ALT,D0
    CMP.W   #80,D0
    BGE     GO_DOCK
    BRA     DO_FLY

GO_DOCK:
    MOVE.B  #2,STATE          ; Switch to docking state
    BRA     MAIN_LOOP

DO_FLY_TLI:
    BSR     SHOW_STATS        ; Update altitude
    
    ADDQ.W  #2,ALT            ; Faster climb for TLI burn
    
    BSR     ERASE_ROCKET      ; Clear old position
    BSR     DRAW_STARS        ; Background
    
    MOVE.L  #4,D1
    MOVE.B  #23,D0            TRAP #15     ; Delay
    
    MOVE.W  ALT,D0
    CMP.W   #180,D0           ; TLI complete at alt 180
    BGE     GO_DOCK2
    BRA     DO_FLY_TLI

GO_DOCK2:
    MOVE.W  #10,CSM_X         ; Reset docking positions
    MOVE.B  #2,STATE          ; Back to docking phase
    BRA     MAIN_LOOP


*-------------------------------------------------------
* PHASE 2: DOCKING
*-------------------------------------------------------
DO_DOCK:
    BSR ERASE_CSM
    BSR ERASE_LM

    MOVE.W  CSM_X,D4
    MOVE.W  #10,D3
    LEA     PTR_CSM,A0
    MOVE.W  #5,D2
    BSR     DRAW_SPRITE

    MOVE.W  LM_X,D4
    MOVE.W  #6,D3
    LEA     PTR_LM_UP,A0
    MOVE.W  #5,D2
    BSR     DRAW_SPRITE

    MOVE.B  #18,D0
    TRAP    #15

    CMP.L   #1,D1
    BEQ     M_L
    CMP.L   #2,D1
    BEQ     M_R
    CMP.L   #3,D1
    BEQ     M_D

    BRA     DO_DOCK
    
M_L:
    CMP.W   #0,CSM_X
    BLE     DO_DOCK
    SUBQ.W  #5,CSM_X
    BRA     DO_DOCK
M_R:
    CMP.W   #71,CSM_X
    BGE     DO_DOCK
    ADDQ.W  #5,CSM_X
    BRA     DO_DOCK
M_D:
    MOVE.W  CSM_X,D0
    SUB.W   LM_X,D0
    BSR     ABS               ; Difference in X (distance)
    CMP.W   #5,D0             ; If within 5 pixels, it's aligned
    BLE     D_OK
    BRA     DO_DOCK
D_OK:
    MOVE.B  DOCKED,D0         ; Check if first or second docking
    CMP.B   #1,D0
    BEQ     SECOND_DOCK
    
FIRST_DOCK:
    MOVE.B  #1,DOCKED         ; Mark first docking complete
    BSR     CLEAR_SCREEN
    BSR     SHOW_STATS
    
    LEA     TLI_PROMPT,A1     ; "PRESS 1 FOR TLI BURN!"
    MOVE.W  #$1400,D1         ; Row 20, col 0
    MOVE.B  #11,D0            
    TRAP #15
    MOVE.B  #14,D0            
    TRAP #15
    
    MOVE.B  #18,D0            
    TRAP #15                  ; Wait for input
    CMP.L   #1,D1
    BNE     DO_DOCK
    
    MOVE.B  #0,DOCKED         ; Reset for second docking
    MOVE.W  #10,CSM_X         ; Reset CSM position
    MOVE.B  #4,STATE          ; Go to FLY_TLI
    BRA     MAIN_LOOP
    
SECOND_DOCK:
    CLR.W   LAND_VY
    MOVE.W  #2,LAND_Y
    MOVE.B  #3,STATE          ; Go to LANDING
    BRA     MAIN_LOOP

*-------------------------------------------------------
* PHASE 3: LUNAR LANDING
*-------------------------------------------------------
DO_LAND:
    BSR     ERASE_LM        ; Clear old LM position
    BSR     SHOW_STATS      ; Update HUD
    
    ADDQ.W  #1,LAND_VY      ; Gravity
    MOVE.W  LAND_VY,D0
    ADD.W   D0,LAND_Y       ; Update Y
    
    ; Lunar surface (static)
    MOVE.W  #$1600,D1
    MOVE.B  #11,D0          TRAP #15
    LEA     SURFACE,A1
    MOVE.B  #14,D0          TRAP #15
    
    ; Draw new LM position
    MOVE.W  #25,D4
    MOVE.W  LAND_Y,D3
    LEA     PTR_LM,A0
    MOVE.W  #5,D2
    BSR     DRAW_SPRITE
    
    CMP.W   #18,LAND_Y      BGE     L_HIT
    
    LEA     LAND_KEYS,A1
    BSR     PRINT_INPUT_LINE
    MOVE.B  #18,D0          TRAP #15
    CMP.L   #1,D1           BEQ     L_UP
    BRA     DO_LAND
    
L_UP:
    SUBI.W  #4,LAND_VY
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

ERASE_PROMPT:
    MOVE.W  #$1402,D1      ; Same row/column as the launch text
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANK_PROMPT,A1
    MOVE.B  #14,D0
    TRAP    #15
    RTS

BLANK_PROMPT: DC.B '                     ',0  ; Same length as launch text

ERASE_ROCKET:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  #35,D4         ; Same X as rocket
    MOVE.W  #5,D3          ; Same Y start
    MOVE.W  #15,D2         ; Height of rocket
    LEA     BLANKLINE,A1
ER_R:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     ER_R
    MOVEM.L (A7)+,D0-D5/A0-A1
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

BLANKLINE: DC.B '         ',0   ; 9 spaces (matches sprite width)

ERASE_LM:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  LM_X,D4           ; LM position (fixed)
    MOVE.W  #8,D3
    MOVE.W  #5,D2
    LEA     BLANKLINE,A1      ; Same blank line works (same width)
ER_LM_L:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     ER_LM_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

DRAW_STARS:
    MOVE.W  #$0502,D1
    BSR     P_S
    MOVE.W  #$350A,D1
    BSR     P_S
    RTS
P_S:
    MOVE.B  #11,D0
    TRAP    #15                  ; Set cursor
    LEA STAR,A1
    MOVE.B  #14,D0
    TRAP    #15                  ; Display "*"
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
    MOVE.W  #$0018,D1
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.B  #14,D0
    TRAP    #15
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
TLI_PROMPT: DC.B    'PRESS 1 FOR TLI BURN' ,0
WIN_MSG:    DC.B    13,10,'SUCCESS!',0
CRASH_MSG:  DC.B    13,10,'CRASH!',0
SURFACE:    DC.B    '________________________________________________',0

PTR_SATURN: DC.L S1,S2,S3,S4,S5,S6,S7,S8,S9,S10,S11,S12,S13,S14,S15
PTR_UPPER:  DC.L S1,S2,S3,S4,S5,S6,S14,S15
PTR_CSM:    DC.L C1,C2,C3,C4,C5
PTR_LM:     DC.L L1,L2,L3,L4,L5
PTR_LM_UP:  DC.L U1,U2,U3,U4,U5

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

U1: DC.B ' \ __ / ',0
U2: DC.B ' _|__|_ ',0
U3: DC.B ' [    ] ',0
U4: DC.B '  \__/  ',0
U5: DC.B '   ''   ',0

    END START
*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~4~
