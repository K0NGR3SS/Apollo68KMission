*-----------------------------------------------------------
* Title      : Apollo 11 Mission
* Written by : Nazariy Buryak
* Date       : 18/02/2025
* Description: Apollo 11 Mission
*-----------------------------------------------------------

    ORG $1000

*-------------------------------------------------------
* CONSTANTS
*-------------------------------------------------------
PAD_STATE       EQU 0
FLY_STATE       EQU 1
DOCK_STATE      EQU 2
FLY_DOCKED      EQU 3
LAND_STAGE      EQU 4

; screen layout constants
CSM_ROW         EQU 10
LM_ROW          EQU 5
SPRITE_H        EQU 5

SCREEN_WIDTH    EQU 80
SCREEN_HEIGHT   EQU 25

; rocket/pad specific constants
ROCKET_H        EQU 19            ; number of rows in Saturn sprite
PAD_COL         EQU 35            ; column where pad/rocket are centred
PAD_START_ROW   EQU SCREEN_HEIGHT ; initial pad row (bottom of screen)
CENTER_ROW      EQU 12          ; vertical centre for flight (approx)
PAD_HEIGHT      EQU 2             ; height of launch pad graphic

; Landing Module Unit (LMU) constants
LMU_START_X     EQU 40              ; Start in middle of screen
LMU_START_Y     EQU 2               ; Start near top
GRAVITY         EQU 1               ; Gravity pull per frame
LMU_THRUST      EQU 2               ; Thrust power (opposes gravity)
SURFACE_Y       EQU 20              ; Row where moon surface is
LANDING_ZONE_X1 EQU 25              ; Left edge of safe landing zone
LANDING_ZONE_X2 EQU 55              ; Right edge of safe landing zone
FRAME_DELAY     EQU 8

; Easy68K screen memory base address
SCREEN_MEM      EQU $E00000
SCREEN_COLS     EQU 80
SCREEN_ROWS     EQU 25

; BG image size: 80 cols x 25 rows, each cell = 2 bytes (char + attribute)
BG_SIZE         EQU SCREEN_COLS*SCREEN_ROWS*2

*-------------------------------------------------------
* VARIABLES
*-------------------------------------------------------
    ORG $4000

STATE:          DC.B    0
                DS.B    1           ; Padding for word alignment
ALT:            DC.W    0
PAD_ROW:        DC.W    0           ; current pad vertical position
OLD_PAD_ROW:    DC.W    0           ; previous pad position (for erasing)
CSM_X:          DC.W    10
OLD_CSM_X:      DC.W    10
CSM_Y:          DC.W    12
OLD_CSM_Y:      DC.W    12
LM_X:           DC.W    40
DOCKED_ALT:     DC.W    0
LANDING_INIT:   DC.W    0

; LMU physics variables
LMU_X:          DC.W    0           ; Current X position (column)
LMU_Y:          DC.W    0           ; Current Y position (row)
LMU_VX:         DC.W    0           ; Horizontal velocity
LMU_VY:         DC.W    0           ; Vertical velocity
OLD_LMU_X:      DC.W    0           ; Previous X for erasing
OLD_LMU_Y:      DC.W    0           ; Previous Y for erasing

; Button states (set by input handler)
BUTTON_LEFT:    DC.B    0
BUTTON_RIGHT:   DC.B    0
BUTTON_THRUST:  DC.B    0
GRAV_COUNT:     DC.W    0
                DS.B    1           ; Padding
*-------------------------------------------------------
* START
*-------------------------------------------------------
    ORG $1000
START:
    BSR     CLEAR_SCREEN

MAIN_LOOP:
    MOVE.B  STATE,D0
    CMP.B   #PAD_STATE,D0
    BEQ     DO_PAD
    CMP.B   #FLY_STATE,D0
    BEQ     DO_FLY
    CMP.B   #DOCK_STATE,D0
    BEQ     DO_DOCK
    CMP.B   #FLY_DOCKED,D0
    BEQ     DO_FLY_DOCKED
    CMP.B   #LAND_STAGE,D0
    BEQ     DO_LANDING
    BRA     END_GAME

*-------------------------------------------------------
* PHASE 0: PRE-LAUNCH (PAD)
*-------------------------------------------------------
DO_PAD:
    ; draw launch pad + rocket at bottom of screen
    BSR     CLEAR_SCREEN
    BSR     SHOW_STATS
    BSR     DRAW_STARS
    ; compute rocket row so its base sits on bottom
    MOVE.W  #PAD_START_ROW,D3      ; start from bottom
    SUB.W   #ROCKET_H,D3           ; adjust for rocket height
    MOVE.W  #PAD_COL,D4
    BSR     DRAW_PAD_ROCKET        ; uses D3 and D4 now
    ; draw pad beneath rocket
    MOVE.W  #PAD_START_ROW,D3
    MOVE.W  #PAD_COL,D4
    MOVE.W  #PAD_HEIGHT,D2
    LEA     PTR_PAD,A0
    BSR     DRAW_SPRITE

WAIT_LAUNCH:
    MOVE.W  #$1402,D1              ; position cursor
    MOVE.B  #11,D0
    TRAP    #15
    LEA     PROMPT_LAUNCH,A1
    MOVE.B  #14,D0
    TRAP    #15

    MOVE.B  #18,D0                 ; blocking read
    TRAP    #15
    CMP.B   #'1',D1
    BNE     WAIT_LAUNCH

    ; countdown animation
    BSR     COUNTDOWN

    BSR     CLEAR_SCREEN
    CLR.W   PAD_ROW               ; reset pad tracking
    CLR.W   OLD_PAD_ROW
    MOVE.B  #FLY_STATE,STATE
    BRA     MAIN_LOOP

*-------------------------------------------------------
* PHASE 1: FLIGHT
*-------------------------------------------------------
DO_FLY:
    BSR     SHOW_STATS
    ADDQ.W  #1,ALT

    ; erase old rocket
    MOVE.W  #PAD_COL,D4
    MOVE.W  #CENTER_ROW,D3
    MOVE.W  #ROCKET_H,D2
    BSR     ERASE_ROCKET

    ; erase previous pad if it existed
    MOVE.W  OLD_PAD_ROW,D3
    TST.W   D3
    BEQ     SKIP_ERASE_PAD
    MOVE.W  #PAD_COL,D4
    MOVE.W  #PAD_HEIGHT,D2
    BSR     ERASE_ROCKET
SKIP_ERASE_PAD:

    ; recalc pad position based on altitude
    MOVE.W  ALT,D0               ; half altitude to slow pad disappearance
    ASR.W   #1,D0
    MOVE.W  #PAD_START_ROW,D1
    SUB.W   D0,D1               ; new pad row
    MOVE.W  D1,PAD_ROW
    MOVE.W  PAD_ROW,OLD_PAD_ROW ; remember for next frame

    ; stars are always drawn every frame
    BSR     DRAW_STARS

    ; draw pad if still on screen
    TST.W   PAD_ROW
    BLT     SKIP_PAD_DRAW
    MOVE.W  PAD_ROW,D3
    MOVE.W  #PAD_COL,D4
    MOVE.W  #PAD_HEIGHT,D2
    LEA     PTR_PAD,A0
    BSR     DRAW_SPRITE

SKIP_PAD_DRAW:
    ; rocket stays centred vertically
    MOVE.W  #CENTER_ROW,D3
    MOVE.W  #PAD_COL,D4

    ; separation threshold unchanged
    MOVE.W  ALT,D0
    CMP.W   #45,D0
    BGT     FLY_SEP
    BSR     DRAW_FULL_ROCKET
    BRA     FLY_STARS
FLY_SEP:
    ; erase full rocket at centre before showing upper stage
    MOVE.W  #PAD_COL,D4
    MOVE.W  #CENTER_ROW,D3
    MOVE.W  #ROCKET_H,D2
    BSR     ERASE_ROCKET
    BSR     DRAW_UPPER_STAGE
FLY_STARS:
    MOVE.L  #4,D1
    MOVE.B  #23,D0
    TRAP    #15
    MOVE.W  ALT,D0
    CMP.W   #80,D0
    BGE     GO_DOCK
    BRA     DO_FLY
GO_DOCK:
    BSR     ERASE_UPPER_STAGE
    BSR     CLEAR_SCREEN
    MOVE.B  #DOCK_STATE,STATE
    BRA     MAIN_LOOP

*-------------------------------------------------------
* PHASE 2: DOCKING
*-------------------------------------------------------
DO_DOCK:
    BSR     CLEAR_SCREEN

DOCK_LOOP:
    BSR     SHOW_STATS

    ; Erase old CSM position
    MOVE.W  OLD_CSM_X,D4
    MOVE.W  OLD_CSM_Y,D3
    BSR     ERASE_CSM

    ; Draw LM (static)
    MOVE.W  LM_X,D4
    MOVE.W  #LM_ROW,D3
    LEA     PTR_LM_UP,A0
    MOVE.W  #SPRITE_H,D2
    BSR     DRAW_SPRITE

    ; Draw CSM (moving)
    MOVE.W  CSM_X,D4
    MOVE.W  CSM_Y,D3
    LEA     PTR_CSM,A0
    MOVE.W  #SPRITE_H,D2
    BSR     DRAW_SPRITE

    MOVE.W  #$1500,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     DOCK_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15

    ; Read keyboard (non-blocking)
    MOVE.B  #18,D0
    TRAP    #15

    ; Save old position before moving
    MOVE.W  CSM_X,OLD_CSM_X
    MOVE.W  CSM_Y,OLD_CSM_Y

    CMP.B   #1,D1
    BEQ     M_U
    CMP.B   #2,D1
    BEQ     M_S
    CMP.B   #3,D1
    BEQ     M_L
    CMP.B   #4,D1
    BEQ     M_R
    CMP.B   #5,D1
    BEQ     M_D
    BRA     DOCK_LOOP

M_L:
    SUBQ.W  #2,CSM_X
    BRA     DOCK_LOOP
M_R:
    ADDQ.W  #2,CSM_X
    BRA     DOCK_LOOP
M_U:
    SUBQ.W  #1,CSM_Y
    BRA     DOCK_LOOP
M_S:
    ADDQ.W  #1,CSM_Y
    BRA     DOCK_LOOP
M_D:
    ; Check X alignment
    MOVE.W  CSM_X,D0
    SUB.W   LM_X,D0
    BSR     ABS
    CMP.W   #3,D0
    BGT     DOCK_LOOP
    ; Check Y alignment
    MOVE.W  CSM_Y,D0
    SUB.W   #LM_ROW+5,D0
    BSR     ABS
    CMP.W   #1,D0
    BGT     DOCK_LOOP
D_OK:
    CLR.W   DOCKED_ALT
    MOVE.B  #FLY_DOCKED,STATE
    BRA     MAIN_LOOP

*-------------------------------------------------------
* PHASE 3: JOINT FLIGHT (DOCKED)
*-------------------------------------------------------
DO_FLY_DOCKED:
    TST.W   DOCKED_ALT
    BNE     DFD_SKIP_CLEAR
    BSR     CLEAR_SCREEN
DFD_SKIP_CLEAR:
    BSR     SHOW_STATS
    ADDQ.W  #1,ALT
    ADDQ.W  #1,DOCKED_ALT

    BSR     ERASE_JOINT
    BSR     DRAW_STARS
    BSR     DRAW_JOINT

    MOVE.L  #4,D1
    MOVE.B  #23,D0
    TRAP    #15

    MOVE.W  DOCKED_ALT,D0
    CMP.W   #50,D0
    BGE     GO_LAND
    BRA     DO_FLY_DOCKED

GO_LAND:
    BSR     CLEAR_SCREEN
    MOVE.B  #LAND_STAGE,STATE
    BRA     MAIN_LOOP

DRAW_JOINT:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  #30,D4
    MOVE.W  #5,D3
    LEA     PTR_LM_UP,A0
    MOVE.W  #5,D2
    BSR     DRAW_SPRITE
    MOVE.W  #9,D3
    LEA     PTR_CSM_FLY,A0
    MOVE.W  #6,D2
    BSR     DRAW_SPRITE
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

ERASE_JOINT:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  #30,D4
    MOVE.W  #4,D3
    MOVE.W  #10,D2
EJ_L:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     EJ_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

*-------------------------------------------------------
* PHASE 4: LUNAR LANDING
*-------------------------------------------------------
DO_LANDING:
    ; One-time initialisation
    TST.W   LANDING_INIT
    BNE     SKIP_LANDING_INIT
    BSR     CLEAR_SCREEN            ; <-- FIX: clear screen on entry
    BSR     DRAW_MOON_SURFACE       ; Draw ASCII moon background once
    BSR     INIT_LMU_LANDING
    MOVE.W  #1,LANDING_INIT
SKIP_LANDING_INIT:

    BSR     READ_LANDING_INPUT
    BSR     ERASE_LMU
    BSR     UPDATE_LMU
    BSR     DRAW_LMU
    BSR     SHOW_LANDING_STATS
    BSR     CHECK_LANDING

    ; Frame delay � controls game speed / gravity feel
    MOVE.L  #FRAME_DELAY,D1
    MOVE.B  #23,D0
    TRAP    #15

    BRA     DO_LANDING

READ_LANDING_INPUT:
    MOVEM.L D0-D1,-(A7)

    ; Clear old button states
    CLR.B   BUTTON_LEFT
    CLR.B   BUTTON_RIGHT
    CLR.B   BUTTON_THRUST

    MOVE.B  #19,D0          ; Non-blocking keyboard read
    TRAP    #15             ; D1 = key code, or 0 if none

    TST.L   D1
    BEQ     RLI_DONE

    CMP.B   #'3',D1
    BEQ     SET_LEFT
    CMP.B   #'a',D1
    BEQ     SET_LEFT
    CMP.B   #'d',D1
    BEQ     SET_RIGHT
    CMP.B   #'4',D1
    BEQ     SET_RIGHT
    CMP.B   #'w',D1
    BEQ     SET_THRUST
    CMP.B   #'1',D1
    BEQ     SET_THRUST
    CMP.B   #' ',D1         ; Space bar also fires thrust
    BEQ     SET_THRUST
    BRA     RLI_DONE

SET_LEFT:
    MOVE.B  #1,BUTTON_LEFT
    BRA     RLI_DONE
SET_RIGHT:
    MOVE.B  #1,BUTTON_RIGHT
    BRA     RLI_DONE
SET_THRUST:
    MOVE.B  #1,BUTTON_THRUST

RLI_DONE:
    MOVEM.L (A7)+,D0-D1
    RTS

*-------------------------------------------------------
* INIT_LMU_LANDING
* Resets the LMU to starting position with zero velocity.
*-------------------------------------------------------
INIT_LMU_LANDING:
    MOVE.W  #LMU_START_X,LMU_X
    MOVE.W  #LMU_START_Y,LMU_Y
    MOVE.W  #LMU_START_X,OLD_LMU_X
    MOVE.W  #LMU_START_Y,OLD_LMU_Y
    CLR.W   LMU_VX
    CLR.W   LMU_VY
    RTS

*-------------------------------------------------------
* UPDATE_LMU
* Gravity applies every 4 frames via GRAV_COUNT.
* Thrust and movement apply every frame.
*-------------------------------------------------------
UPDATE_LMU:
    MOVEM.L D0,-(A7)

    ; Save old position for erasing
    MOVE.W  LMU_X,OLD_LMU_X
    MOVE.W  LMU_Y,OLD_LMU_Y

    ; Only apply gravity every 4 frames
    ADDQ.W  #1,GRAV_COUNT
    MOVE.W  GRAV_COUNT,D0
    CMP.W   #4,D0
    BLT     UL_SKIP_GRAV
    CLR.W   GRAV_COUNT
    ADD.W   #GRAVITY,LMU_VY
UL_SKIP_GRAV:

    ; Thrust cancels downward velocity (apply every frame)
    TST.B   BUTTON_THRUST
    BEQ     UL_NO_THRUST
    SUB.W   #LMU_THRUST,LMU_VY
    ; Don't let thrust push upward too fast
    MOVE.W  LMU_VY,D0
    CMP.W   #-3,D0
    BGE     UL_NO_THRUST
    MOVE.W  #-3,LMU_VY
UL_NO_THRUST:

    ; Horizontal movement
    TST.B   BUTTON_LEFT
    BEQ     UL_NO_LEFT
    MOVE.W  LMU_VX, D0
    SUB.W   D0, LMU_X
UL_NO_LEFT:
    TST.B   BUTTON_RIGHT
    BEQ     UL_NO_RIGHT
    MOVE.W  LMU_VY, D0
    ADD.W   D0, LMU_Y
UL_NO_RIGHT:

    ; Clamp horizontal to screen bounds
    MOVE.W  LMU_X,D0
    CMP.W   #0,D0
    BGE     UL_NO_CLAMP_L
    CLR.W   LMU_X
UL_NO_CLAMP_L:
    MOVE.W  LMU_X,D0
    CMP.W   #SCREEN_WIDTH-8,D0
    BLE     UL_NO_CLAMP_R
    MOVE.W  #SCREEN_WIDTH-8,LMU_X
UL_NO_CLAMP_R:

    ; Terminal velocity cap
    MOVE.W  LMU_VY,D0
    CMP.W   #4,D0
    BLE     UL_NO_CLAMP_V
    MOVE.W  #4,LMU_VY
UL_NO_CLAMP_V:

    ; Stop going above screen
    MOVE.W  LMU_Y,D0
    CMP.W   #0,D0
    BGE     UL_UPDATE_POS
    CLR.W   LMU_Y
    CLR.W   LMU_VY
UL_UPDATE_POS:

    ; Update vertical position
    MOVE.W  LMU_VY,D0
    ADD.W   D0,LMU_Y

    MOVEM.L (A7)+,D0
    RTS

*-------------------------------------------------------
* DRAW_MOON_SURFACE
* Draws a full ASCII moon landscape across rows 20-24.
* Row 19 = flat landing zone marker.
* Called once on landing init.
*-------------------------------------------------------
DRAW_MOON_SURFACE:
    MOVEM.L D0-D4/A0-A1,-(A7)

    ; Draw space (stars) rows 1-18
    MOVE.W  #1,D3
MS_SPACE_L:
    MOVE.W  #0,D4
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     SPACE_LINE,A1
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    CMP.W   #19,D3
    BLT     MS_SPACE_L

    ; Draw surface row 20 (top of terrain)
    MOVE.W  #20,D3
    MOVE.W  #0,D4
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     SURFACE_TOP,A1
    MOVE.B  #14,D0
    TRAP    #15

    ; Draw solid moon rows 21-24
    MOVE.W  #21,D3
MS_GROUND_L:
    MOVE.W  #0,D4
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     GROUND_LINE,A1
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    CMP.W   #25,D3
    BLT     MS_GROUND_L

    ; Also draw a couple of stars manually
    MOVE.W  #$0308,D1
    BSR     P_S
    MOVE.W  #$1503,D1
    BSR     P_S
    MOVE.W  #$4A06,D1
    BSR     P_S
    MOVE.W  #$300B,D1
    BSR     P_S

    MOVEM.L (A7)+,D0-D4/A0-A1
    RTS
*-------------------------------------------------------
* DRAW_LMU
* Draws the Lunar Module at current LMU_X, LMU_Y.
* Uses TRAP #15 task 11 (cursor position) + task 14 (print).
*-------------------------------------------------------
DRAW_LMU:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  LMU_X,D4
    MOVE.W  LMU_Y,D3
    LEA     PTR_LM_LAND,A0
    MOVE.W  #LM_LAND_H,D2
    BSR     DRAW_SPRITE
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

*-------------------------------------------------------
* ERASE_LMU
* Blanks the LMU sprite at OLD_LMU_X, OLD_LMU_Y.
*-------------------------------------------------------
ERASE_LMU:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  OLD_LMU_X,D4
    MOVE.W  OLD_LMU_Y,D3
    MOVE.W  #LM_LAND_H,D2
ELU_L:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     BLANKLINE_WIDE,A1
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     ELU_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

*-------------------------------------------------------
* SHOW_LANDING_STATS
* Displays velocity and position info at top of screen.
*-------------------------------------------------------
SHOW_LANDING_STATS:
    MOVEM.L D0-D1,-(A7)

    ; Print "VY:" label at top-left
    MOVE.W  #$0000,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     VY_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15

    ; Print vertical velocity value
    MOVE.W  LMU_VY,D1
    EXT.L   D1
    MOVE.B  #3,D0
    TRAP    #15

    ; Print "  X:" after velocity
    LEA     X_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15

    ; Print X position
    MOVE.W  LMU_X,D1
    EXT.L   D1
    MOVE.B  #3,D0
    TRAP    #15

    MOVEM.L (A7)+,D0-D1
    RTS

*-------------------------------------------------------
* CHECK_LANDING
* Checks if LMU has reached SURFACE_Y.
* If within landing zone and slow enough -> success.
* Otherwise -> crash.
*-------------------------------------------------------
CHECK_LANDING:
    MOVEM.L D0-D1,-(A7)

    ; LMU bottom = LMU_Y + LM_LAND_H - 1
    MOVE.W  LMU_Y,D0
    ADD.W   #LM_LAND_H,D0       ; D0 = row of bottom pixel of LMU

    CMP.W   #SURFACE_Y,D0
    BLT     CL_DONE             ; Still in the air

    ; Clamp LMU so it sits exactly on surface, doesn't go through
    MOVE.W  #SURFACE_Y,D0
    SUB.W   #LM_LAND_H,D0
    MOVE.W  D0,LMU_Y
    CLR.W   LMU_VY

    ; Check horizontal position within landing zone
    MOVE.W  LMU_X,D0
    CMP.W   #LANDING_ZONE_X1,D0
    BLT     CL_CRASH
    CMP.W   #LANDING_ZONE_X2,D0
    BGT     CL_CRASH

    ; --- SUCCESSFUL LANDING ---
    MOVEM.L (A7)+,  D0-D1
    BSR     CLEAR_SCREEN
    MOVE.W  #$050A,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     LAND_SUCCESS,A1
    MOVE.B  #14,D0
    TRAP    #15
    BRA     CL_END_GAME

CL_CRASH:
    MOVEM.L (A7)+, D0-D1
    BSR     CLEAR_SCREEN
    MOVE.W  #$050A,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     LAND_CRASH,A1
    MOVE.B  #14,D0
    TRAP    #15

CL_END_GAME:
    MOVE.B  #18,D0
    TRAP    #15
    BRA     END_GAME

CL_DONE:
    MOVEM.L (A7)+,D0-D1
    RTS
*-------------------------------------------------------
* RENDERING SUBROUTINES
*-------------------------------------------------------
DRAW_PAD_ROCKET:
    ; draw the full Saturn sprite using caller supplied row (D3) and column (D4)
    LEA     PTR_SATURN,A0
    MOVE.W  #ROCKET_H-1,D2
    BSR     DRAW_SPRITE
    RTS

;-------------------------------------------------------
; COUNTDOWN - display 3,2,1,GO! with brief pauses
;-------------------------------------------------------
COUNTDOWN:
    MOVEM.L D0-D1,-(A7)

    MOVE.W  #$1402,D1          ; set cursor at some fixed location
    MOVE.B  #11,D0
    TRAP    #15

    ; show '3'
    LEA     COUNT3,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.L  #$1500,D1          ; simple delay
    MOVE.B  #23,D0
    TRAP    #15

    ; show '2'
    LEA     COUNT2,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.L  #$1500,D1
    MOVE.B  #23,D0
    TRAP    #15

    ; show '1'
    LEA     COUNT1,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.L  #$1500,D1
    MOVE.B  #23,D0
    TRAP    #15

    ; show GO!
    LEA     COUNTGO,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.L  #$1500,D1
    MOVE.B  #23,D0
    TRAP    #15

    MOVEM.L (A7)+,D0-D1
    RTS

DRAW_FULL_ROCKET:
    LEA     PTR_SATURN,A0
    MOVE.W  #19,D2
    MOVE.W  #35,D4
    BSR     DRAW_SPRITE
    RTS

DRAW_UPPER_STAGE:
    LEA     PTR_UPPER,A0
    MOVE.W  #11,D2
    MOVE.W  #35,D4
    BSR     DRAW_SPRITE
    RTS

*-------------------------------------------------------
* DRAW_SPRITE
* D4 = column, D3 = starting row, D2 = number of rows
* A0 = pointer table (each entry is a DC.L to a string)
*-------------------------------------------------------
DRAW_SPRITE:
    MOVEM.L D0-D5/A0-A1,-(A7)
DS_L:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.L  (A0)+,A1
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     DS_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

ERASE_ROCKET:
    ; now a generic erase routine - caller must supply D4=column, D3=row, D2=height
    MOVEM.L D0-D5/A0-A1,-(A7)
    LEA     BLANKLINE_WIDE,A1
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

ERASE_UPPER_STAGE:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  #35,D4
    MOVE.W  #5,D3
    MOVE.W  #11,D2
    LEA     BLANKLINE_WIDE,A1
ER_UP_L:
    MOVE.W  D4,D1
    LSL.W   #8,D1
    OR.B    D3,D1
    MOVE.B  #11,D0
    TRAP    #15
    MOVE.B  #14,D0
    TRAP    #15
    ADDQ.W  #1,D3
    SUBQ.W  #1,D2
    BNE     ER_UP_L
    MOVEM.L (A7)+,D0-D5/A0-A1
    RTS

ERASE_CSM:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  OLD_CSM_X,D4
    MOVE.W  OLD_CSM_Y,D3
    MOVE.W  #SPRITE_H,D2
    LEA     BLANKLINE_WIDE,A1
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

ERASE_LM:
    MOVEM.L D0-D5/A0-A1,-(A7)
    MOVE.W  LM_X,D4
    MOVE.W  #LM_ROW,D3
    MOVE.W  #SPRITE_H,D2
    LEA     BLANKLINE_WIDE,A1
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
    TRAP    #15
    LEA     STAR,A1
    MOVE.B  #14,D0
    TRAP    #15
    RTS

CLEAR_SCREEN:
    MOVE.B  #12,D0
    TRAP    #15
    RTS

SHOW_STATS:
    MOVE.W  #$0014,D1
    MOVE.B  #11,D0
    TRAP    #15
    LEA     ALT_MSG,A1
    MOVE.B  #14,D0
    TRAP    #15
    MOVE.W  ALT,D1
    EXT.L   D1
    MOVE.B  #3,D0
    TRAP    #15
    RTS

ABS:
    TST.W   D0
    BPL     A_X
    NEG.W   D0
A_X:
    RTS

END_GAME:
    MOVE.B  #9,D0
    TRAP    #15

*-------------------------------------------------------
* DATA
*-------------------------------------------------------
STAR:           DC.B    '*',0
ALT_MSG:        DC.B    'ALTITUDE: ',0
PROMPT_LAUNCH:  DC.B    '1 to Lift Off!',0
COUNT3:          DC.B    '3',0
COUNT2:          DC.B    '2',0
COUNT1:          DC.B    '1',0
COUNTGO:         DC.B    'GO!',0
DOCK_MSG:       DC.B    'Move: 1=Up 2=Dn 3=Lt 4=Rt 5=Dock',0
BLANKLINE_WIDE: DC.B    '                    ',0
VY_MSG:         DC.B    'VY:',0
X_MSG:          DC.B    '  X:',0
LAND_SUCCESS:   DC.B    '*** EAGLE HAS LANDED! ***',0
LAND_CRASH:     DC.B    '*** CRASH LANDING! MISSION FAILED ***',0
SPACE_LINE:  DC.B '                                                                                ',0                               ',0
SURFACE_TOP: DC.B '~~~~\/\/\________________________________________/\/\/\/\/\/\/\/\/\/\/\/\/\/~~~~',0
GROUND_LINE: DC.B '################################################################################',0

; Sprite pointer tables
PTR_SATURN:  DC.L S1,S2,S3,S4,S5,S6,S7,S8,S9,S10,S11,S12,S13,S14,S15,S16,S17,S18,S19
PTR_PAD:     DC.L P1,P2

P1:          DC.B '   |=====|   ',0
P2:          DC.B '  / ===== \  ',0
PTR_UPPER:   DC.L S2,S3,S4,S5,S6,S7,S8,S9,S10,S18,S19
PTR_CSM:     DC.L C1,C2,C3,C4,C5
PTR_CSM_FLY: DC.L C1,C2,C3,C4,C5,C6
PTR_LM_UP:   DC.L U1,U2,U3,U4,U5
PTR_LM_LAND: DC.L L1,L2,L3,L4,L5

LM_LAND_H    EQU 5           ; Height of landing LM sprite

; Saturn V rocket lines
S1:  DC.B '     |     ',0
S2:  DC.B '     !     ',0
S3:  DC.B '    / \    ',0
S4:  DC.B '   |   |   ',0
S5:  DC.B '   |   |   ',0
S6:  DC.B '   |   |   ',0
S7:  DC.B '   |   |   ',0
S8:  DC.B '   |   |   ',0
S9:  DC.B '   |   |   ',0
S10: DC.B '   |---|   ',0
S11: DC.B '   | | |   ',0
S12: DC.B '   | | |   ',0
S13: DC.B '   | | |   ',0
S14: DC.B '   | | |   ',0
S15: DC.B '   | U |   ',0
S16: DC.B '  /| S |\  ',0
S17: DC.B ' |_|_A_|_| ',0
S18: DC.B '   /\|/\   ',0
S19: DC.B '   V V V   ',0

; CSM lines
C1: DC.B '   /\   ',0
C2: DC.B '  /  \  ',0
C3: DC.B ' |    | ',0
C4: DC.B ' |____| ',0
C5: DC.B '  /__\  ',0
C6: DC.B '   VV   ',0

U1: DC.B ' \ __ / ',0
U2: DC.B ' _|__|_ ',0
U3: DC.B ' [    ] ',0
U4: DC.B '  \__/  ',0
U5: DC.B '   ''   ',0

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
*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~4~
