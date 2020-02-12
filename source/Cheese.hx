package;

import flixel.util.FlxTimer;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.math.FlxVector;
import flixel.util.FlxColor;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;

class Cheese extends FlxSprite
{
    var followTarget:FlxObject = null;
    var follower:Cheese = null;
    var startPos = new FlxPoint();
    var mode:CheeseState = Idle;
    var flickerTimer = 0.0;
    var eatCallback:()->Void;
    
    public function new(x:Float, y:Float) 
    {
        super(x, y);
        startPos.set(x, y);

        loadGraphic(AssetPaths.cheese_idle__png, true, 32, 32);
        animation.add('idle', [0]);
        animation.add('follow', [0, 1, 2, 3, 4, 5, 6], 12);
        animation.play('idle');
        offset.x = 2;
        width -= 5;
        offset.y = 2;
        height -= 7;
    }
    
    override function update(elapsed:Float):Void
    {
        super.update(elapsed);
        
        if (followTarget != null)
            updateFollow(elapsed);
        
        if (flickerTimer > 0)
        {
            flickerTimer -= elapsed;
            if (flickerTimer < 0)
                flickerTimer = 0;
            final flash = 0xFF * Std.int(flickerTimer / 0.08) % 2;
            setColorTransform(1, 1, 1, 1, flash, flash, flash);
        }
    }
    
    public function startFollow(target:Player):Void
    {
        if (mode != Idle)
            throw "can't follow invalid mode:" + mode.getName();
        if (target == null)
            throw "null follow target";
        
        var animFrame = 0;
        if (target.cheese.length == 0)
            followTarget = target;
        else
        {
            var leadCheese = target.cheese.last();
            followTarget = leadCheese;
            leadCheese.follower = this;
            animFrame = leadCheese.animation.curAnim.curFrame - 1;
            leadCheese.animation.play("follow", true, false, animFrame);
            
            // 
            if (animFrame == -1)
                animFrame += leadCheese.animation.curAnim.numFrames;
        }
        mode = GetAnim;
        solid = false;
        
        // make it start moving a little so it's really clear we just touched it
        animation.play("follow", true, false, animFrame);
        var animDuration = animation.curAnim.numFrames / animation.curAnim.frameRate;
        flickerTimer = animDuration / 2;
        // move in direction player is moving
        final moveTime = animDuration * 0.8;// have some still time
        final amount = 64;
        maxVelocity.set();
        velocity.copyFrom(target.velocity).normalize();
        if (velocity.isZero())
            velocity.y = -1;//straight up
        velocity.scale(2 * amount / moveTime);
        drag.copyFrom(velocity).scale(1 / moveTime);
        if (drag.x < 0) drag.x = -drag.x;
        if (drag.y < 0) drag.y = -drag.y;
        
        // actually start following after animation
        new FlxTimer().start(animDuration,(_)->
        {
            switch (mode)
            {
                case GetAnim: mode = StartFollow;
                case ToStart|Idle:// Acceptable, player died before anim complete
                default:
                    throw "anim complete with invalid mode: " + mode.getName();
            }
        });
        // FlxTween.tween(this, { y: y - height * 1.5 }, animDuration,
        //     { ease:FlxEase.backOut
        //     ,   onComplete:(_)->
        //         {
        //             switch (mode)
        //             {
        //                 case GetAnim: mode = StartFollow;
        //                 case ToStart|Idle:// Acceptable, player died before anim complete
        //                 default:
        //                     throw "anim complete with invalid mode: " + mode.getName();
        //             }
        //         }
        //     }
        // );
    }
    
    public function resetToSpawn():Void
    {
        followTarget = null;
        follower = null;
        animation.play("idle");
        mode = ToStart;
        final maxTime = 1.0;
        final minSpeed = 200;
        final distance = Math.sqrt((x - startPos.x) * (x - startPos.x) + (y - startPos.y) * (y - startPos.y));
        flickerTimer = Math.min(maxTime, distance / minSpeed);
        FlxTween.tween(this, { x:startPos.x, y:startPos.y }, flickerTimer,
            { ease:FlxEase.smoothStepInOut
            , onComplete:(_)->
                {
                    solid = true;
                    mode = Idle;
                }
            }
        );
    }
    
    public function sendToMouse(target:Checkpoint, onEat:()->Void):Void
    {
        followTarget = target;
        mode = ToCheckpoint;
        eatCallback = onEat;
        acceleration.set();
        maxVelocity.set();
        drag.set();
    }
    
    function updateFollow(elapsed:Float):Void
    {
        final distance = FlxVector.get(followTarget.x - x, followTarget.y - y);
        final followDistance = Std.is(followTarget, Player) ? 25 : 15;
        switch (mode)
        {
            case GetAnim://nothing
            case StartFollow:
                final maxDistance = followDistance * 2;
                final slowDistance = maxDistance * 2;
                if (distance.lengthSquared > slowDistance * slowDistance)
                {
                    velocity.x += distance.x;
                    velocity.y += distance.y;
                    drag.set(0);
                    maxVelocity.set(400, 400);
                }
                else
                {
                    acceleration.set();
                    maxVelocity.set(400, 400);
                    drag.copyFrom(maxVelocity).scale(8);
                    velocity.x += distance.x;
                    velocity.y += distance.y;
                    
                    if (distance.lengthSquared < maxDistance * maxDistance)
                    {
                        mode = FollowClose;
                        maxVelocity.set(200, 200);
                        drag.copyFrom(maxVelocity).scale(8);
                    }
                }
            case FollowClose:
                final maxDistance = followDistance * 4;
                if (distance.lengthSquared > maxDistance * maxDistance)
                {
                    distance.length -= maxDistance;
                    x += distance.x;
                    y += distance.y;
                    distance.set(followTarget.x - x, followTarget.y - y);
                }
                
                if (distance.lengthSquared > followDistance * followDistance)
                {
                    distance.length -= followDistance;
                    velocity.x = FlxMath.lerp(distance.x / FlxG.elapsed / 8, velocity.x, 0.5);
                    velocity.y = FlxMath.lerp(distance.y / FlxG.elapsed / 8, velocity.y, 0.5);
                }
            case ToCheckpoint:
                velocity.x = distance.x * 4;
                velocity.y = distance.y * 4;
                if (distance.lengthSquared < 15*15)
                {
                    eatCallback();
                    if (follower != null)
                        follower.sendToMouse(cast followTarget, eatCallback);
                    followTarget = null;
                    follower = null;
                    eatCallback = null;
                    kill();
                }
            case _:
                throw "unhandled state" + mode.getName();
        }
        distance.put();
    }
}

enum CheeseState
{
    Idle;
    GetAnim;
    StartFollow;
    FollowClose;
    ToCheckpoint;
    ToStart;
}