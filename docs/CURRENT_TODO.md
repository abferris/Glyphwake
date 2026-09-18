# Current Work To DO

## Bugs
### Player Model
#### General Model
When I walk around and turn, the camera should stay in front of the player model's face. Its in front, so if you look down, you don't see through the stickman model. When you rotate, the stickman model should rotate, and the camera should stay in front of the model's face.
What happens right now:
- When looking straight down, the model is looking through the chest/torso, and so the feet aren't visible.
- When turning, you can eventually turn 180 degrees to look at the player model.
    - the model is rotating, but the camera stays where it is.
What should happen:
- Looking down, i should see my arms, legs, and maybe my chest
- When turning, the camera should stay in front of the model's face the whole time
#### Swimming Model
The swimming model suffers from the same rotation issue. Specifically with the swimming model, the model rotation is not what we want it to. The animation is not angled correctly. when underwater the movement of the model isn't as desired, and the field of view is too far when looking down
What happens right now:
- On the surface, the swimming animation looks like it is simply keeping treading water
    - When on the surface and swimming forward, the body shape is upright.
    - When on the surface and swimming sideways or diagonal, the model is upright.
- When underwater, the model's body is 90 degrees from camera angle
- the field of view is incorrect underwater
    - when underwater I can pan up and look all the way behind me
    - When underwater I can pan down and look all the way to my feet
- Its hard to stay on the surface swimming.
What should happen
- When moving on the water's surface, the body of the model should be angled.
    - when swimming forward, the model should be leading with their head with a breast stroke animation
    - When going to the side, the model should tilt somewhere between 40 and 45 degree angle
    - When going backwards the model should tilt somewhere between a 30 and 35 degree angle
    - When moving diagonally, combine the model change from forward/backward movement with that of the sideways movement model
    - The camera should stay in front of the model's face the whole time
- When moving under the surface the model's body should be fully behind camera 
    - The direction of the model's body be behind the head at a slight angle (currently perpendicular)
    - The Model's body should always be directed to be behind the camera.
    - Idle animation underwater should be oriented in the same way
- Underwater field of view
    - I should not be able to look at my feet by panning up or down
    - the most vertical I should be able to look is directly up and directly down
- To initiate a dive, you should need to be looking down at least 10 or 15 degrees
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
