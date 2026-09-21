# Current Work To DO

## Bugs
### Player Model
#### Swimming Model
The swimming model suffers from the same rotation issue. Specifically with the swimming model, the model rotation is not what we want it to. The animation is not angled correctly. when underwater the movement of the model isn't as desired, and the field of view is too far when looking down
What happens right now:
- Currently we have 2 modes of camera that we can quick toggle for being able to see the model
    - turn Current on for Player/Head/Camera3D and off for DebugChaseCamera_REMOVE_ME.
- On the surface, the swimming animation looks strange
    - when swimming forward, the head of the model flips back and forth and ends up folded
    - When on the surface and swimming sideways, the head of the model is underwater.
    - When on the surface and swimming sideways or diagonal, the model is upright.
- will need to deal with camera later
What should happen
- When moving on the water's surface, the body of the model should be angled.
    - when swimming forward, the model should be leading with their head with a breast stroke animation
    - When going to the side, the model should tilt somewhere between 40 and 45 degree angle
    - When going backwards the model should tilt somewhere between a 30 and 35 degree angle
    - When moving diagonally, combine the model change from forward/backward movement with that of the sideways movement model
    - The camera should stay in front of the model's face the whole time]
- tbd upon camera testing.
- We may want to change the calculation of the model to be around the head, as that is where the camera is.
    - this may have larger implications on refactoring.
### Land Movement
We need to implement a slip mechanic so that players get up steep slopes just by jumping.
### Water
#### Surface
When looking from below, the water's surface cannot really be determined. The surface line should be defined somehow so that you can have some idea of where to go.
#### Under Water
When inside the water volume, there should be a blue-greenish tint to the camera, to create the effect of being underwater. Currently it just looks clear.

# Next Work To Do

- Implementing Rune system
    - passive runes
    - active runes
    - some of this might have been started by
- Creating player interface
    - menus
        - player menu
        - rune setup menu
        - player options
            - camera
                - mouse to rotate
                    - aim on center screen
                - right click to rotate
                    - aim on cursor
            - wasd vs up down right left
            - casting style (click skill and click mouse vs skill smart cast where cursor is)
    - rune hud in game
    - rune slot selection
- Mechanics to create
    - Slippage
    - Breath
    - Mana
    - Health
    - Falling damage
    - casting
        - how to cast skill
        - do i have a skill range help tool?
    - skill selection
    - aiming mechanics (point and click)
- make some goddamn runes and their effects
