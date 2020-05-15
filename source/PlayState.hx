package;

import Cheese;
import Lock;
import OgmoPath;
import OgmoTilemap;
import beat.BeatGame;
import data.Level;
import props.Platform;
import props.BlinkingPlatform;
import props.MovingPlatform;
import ui.BitmapText;
import ui.DialogueSubstate;
import ui.Inputs;
import ui.PauseSubstate;
import ui.MinimapSubstate;
import ui.Minimap;

import io.newgrounds.NG;

import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.effects.FlxFlicker;
import flixel.group.FlxGroup;
import flixel.math.FlxPoint;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.tweens.FlxEase;

import flixel.addons.display.FlxBackdrop;

using zero.utilities.OgmoUtils;
using zero.flixel.utilities.FlxOgmoUtils;

class PlayState extends flixel.FlxState
{
	inline static var USE_NEW_CAMERA = true;
	inline static var FIRST_CHEESE_MSG = "Thanks for the cheese, buddy! ";
	
	var minimap:Minimap;
	var tileSize = 0;
	
	var levels:Map<String, Level> = [];
	var playerCameras:Map<Player, PlayCamera> = [];
	
	var bg:FlxBackdrop;
	var foreground = new FlxGroup();
	var background = new FlxGroup();
	var grpCracks = new FlxTypedGroup<OgmoTilemap>();
	var grpPlayers = new FlxTypedGroup<Player>();
	var grpCheese = new FlxTypedGroup<Cheese>();
	var grpTilemaps = new FlxTypedGroup<OgmoTilemap>();
	var grpPlatforms = new FlxTypedGroup<TriggerPlatform>();
	var grpOneWayPlatforms = new FlxTypedGroup<Platform>();
	var grpSpikes = new FlxTypedGroup<SpikeObstacle>();
	var grpCheckpoint = new FlxTypedGroup<Checkpoint>();
	var grpLockedDoors = new FlxTypedGroup<Lock>();
	var grpMusicTriggers = new FlxTypedGroup<MusicTrigger>();
	var grpSecretTriggers = new FlxTypedGroup<SecretTrigger>();
	var grpCameraTiles = new FlxTypedGroup<CameraTilemap>();
	var grpDecalLayers = new FlxTypedGroup<FlxGroup>();
	var musicName:String;

	var gaveCheese = false;
	var cheeseCountText:BitmapText;
	var dialogueBubble:FlxSprite;
	var cheeseCount = 0;
	var cheeseNeeded = 0;
	var totalCheese = 0;
	var curCheckpoint:Checkpoint;
	var cheeseNeededText:LockAmountText;
	
	override public function create():Void
	{
		playMusic("pillow");
		
		bg = new FlxBackdrop(AssetPaths.dumbbg__png);
		bg.scrollFactor.set(0.75, 0.75);
		bg.alpha = 0.75;
		bg.cameras = [];//prevents it from showing in the dialog substates camera
		#if debug bg.ignoreDrawDebug = true; #end
		
		add(bg);
		add(grpCracks);
		add(background);
		add(grpTilemaps);
		add(grpDecalLayers);
		add(foreground);
		add(grpPlayers);
		
		dialogueBubble = new FlxSprite().loadGraphic(AssetPaths.dialogue__png, true, 32, 32);
		dialogueBubble.animation.add('play', [0, 1, 2, 3], 6);
		dialogueBubble.animation.play('play');
		add(dialogueBubble);
		dialogueBubble.visible = false;
		
		FlxG.worldBounds.set(0, 0, 0, 0);
		FlxG.cameras.remove(FlxG.camera);
		FlxG.camera = null;
		var levelPath = 
			// AssetPaths.dumbassLevel__json;
			// AssetPaths.normassLevel__json;
			AssetPaths.smartassLevel__json;
		createLevel(levelPath);
		minimap = new Minimap(levelPath);
		
		createUI();
	}
	
	function createUI()
	{
		var uiGroup = new FlxGroup();
		var bigCheese = new DisplayCheese(10, 10);
		bigCheese.scrollFactor.set();
		#if debug bigCheese.ignoreDrawDebug = true; #end
		uiGroup.add(bigCheese);
		
		cheeseCountText = new BitmapText(40, 12, "");
		cheeseCountText.scrollFactor.set();
		#if debug cheeseCountText.ignoreDrawDebug = true; #end
		uiGroup.add(cheeseCountText);
		add(uiGroup);
	}
	
	function createLevel(levelPath:String, x = 0.0, y = 0.0):FlxGroup
	{
		var level = new Level();
		var ogmo = FlxOgmoUtils.get_ogmo_package(AssetPaths.levelProject__ogmo, levelPath);
		var map = new OgmoTilemap(ogmo, 'tiles', 0, 3);
		#if debug map.ignoreDrawDebug = true; #end
		map.setTilesCollisions(40, 4, FlxObject.UP);
		level.map = map;
		grpTilemaps.add(map);
		
		var worldBounds = FlxG.worldBounds;
		if (map.x < worldBounds.x) worldBounds.x = map.x;
		if (map.y < worldBounds.y) worldBounds.y = map.y;
		if (map.x + map.width  > worldBounds.right) worldBounds.right = map.x + map.width;
		if (map.y + map.height > worldBounds.bottom) worldBounds.bottom = map.y + map.height;
		
		var crack = new OgmoTilemap(ogmo, 'Crack', "assets/images/");
		#if debug crack.ignoreDrawDebug = true; #end
		grpCracks.add(crack);
		
		var decalGroup = ogmo.level.get_decal_layer('decals').get_decal_group('assets/images/decals');
		for (decal in decalGroup.members)
		{
			(cast decal:FlxObject).moves = false;
			#if debug
			(cast decal:FlxSprite).ignoreDrawDebug = true;
			#end
		}
		
		level.add(map);
		level.add(crack);
		level.add(decalGroup);
		
		ogmo.level.get_entity_layer('BG entities').load_entities(entity_loader.bind(_, background, level));
		ogmo.level.get_entity_layer('FG entities').load_entities(entity_loader.bind(_, foreground, level));
		
		level.cameraTiles = new CameraTilemap(ogmo);
		grpCameraTiles.add(level.cameraTiles);
		
		levels[levelPath] = level;
		return level;
	}
	
	function createPlayer(x:Float, y:Float):Player
	{
		var player = new Player(x, y);
		player.onRespawn.add(onPlayerRespawn);
		grpPlayers.add(player);
		if (curCheckpoint == null)
			curCheckpoint = new Checkpoint(x, y, "");
		
		var camera = new PlayCamera().init(player, 32);
		camera.minScrollX = FlxG.worldBounds.left;
		camera.maxScrollX = FlxG.worldBounds.right;
		camera.minScrollY = FlxG.worldBounds.top;
		camera.maxScrollY = FlxG.worldBounds.bottom;
		
		playerCameras[player] = camera;
		FlxG.cameras.add(camera);
		if (FlxG.camera == null)
			FlxG.camera = camera;
		bg.cameras.push(camera);
		
		return player;
	}

	function entity_loader(e:EntityData, layer:FlxGroup, level:Level)
	{
		var entity:FlxBasic = null;
		switch(e.name)
		{
			case "player": 
				level.player = createPlayer(e.x, e.y);
				level.add(level.player);
				// entity = level.player;
				//layer not used
			case "spider":
				// layer.add(new Enemy(e.x, e.y, OgmoPath.fromEntity(e), e.values.speed));
			case "coins" | "cheese":
				totalCheese++;
				entity = grpCheese.add(new Cheese(e.x, e.y, e.id, true));
			case "blinkingPlatform"|"solidBlinkingPlatform"|"cloudBlinkingPlatform":
				var platform = BlinkingPlatform.fromOgmo(e);
				grpPlatforms.add(platform);
				if (platform.oneWayPlatform)
					grpOneWayPlatforms.add(platform);
				entity = platform;
			case "movingPlatform"|"solidMovingPlatform"|"cloudMovingPlatform":
				var platform = MovingPlatform.fromOgmo(e);
				grpPlatforms.add(platform);
				if (platform.oneWayPlatform)
					grpOneWayPlatforms.add(platform);
				entity = platform;
			case "spike":
				entity = grpSpikes.add(new SpikeObstacle(e.x, e.y, e.rotation));
			case "checkpoint":
				entity = grpCheckpoint.add(Checkpoint.fromOgmo(e));
				// #if debug
				// if (!minimap.checkpoints.exists(rat.ID))
				// 	throw "Non-existent checkpoint id:" + rat.ID;
				// #end
			case "musicTrigger":
				entity = grpMusicTriggers.add(new MusicTrigger(e.x, e.y, e.width, e.height, e.values.song, e.values.fadetime));
			case "secretTrigger":
				trace('ADDED SECRET');
				entity = grpSecretTriggers.add(new SecretTrigger(e.x, e.y, e.width, e.height));
			case 'locked' | 'locked_tall':
				entity = grpLockedDoors.add(Lock.fromOgmo(e));
			case unhandled:
				throw 'Unhandled token:$unhandled';
		}
		
		if (entity != null)
		{
			layer.add(entity);
			level.add(entity);
		}
	}
	
	private var ending:Bool = false;
	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		
		updateCollision();
		
		grpPlayers.forEach
		(
			player->
			{
				checkPlayerState(player);
				minimap.updateSeen(playerCameras[player]);
			}
		);
		
		if (Inputs.justPressed.MAP)
		{
			var player = grpPlayers.members[0];//Todo: check each player
			openSubState(new MinimapSubstate(minimap, player, warpTo));
		}
		
		if (Inputs.justPressed.PAUSE)
			openSubState(new PauseSubstate());
		
		cheeseCountText.text = cheeseCount + (cheeseNeeded > 0 ? "/" + cheeseNeeded : "");
		
		#if debug updateDebugFeatures(); #end
	}
	
	function warpTo(x:Float, y:Float):Void
	{
		grpPlayers.forEach(player->player.hurtAndRespawn(x,y));
	}
	
	inline function updateCollision()
	{
		grpPlayers.forEach(updatePlatforms);
		
		checkDoors();
		updateTriggers();
	}
	
	function updatePlatforms(player:Player)
	{
		// Disable one way platforms when pressing down
		if (player.down)
			grpOneWayPlatforms.forEach((platform)->platform.cloudSolid = false);
		
		var oldPlatform = player.platform;
		player.platform = null;
		FlxG.collide(grpPlatforms, player, 
			function(platform:Platform, _)
			{
				if (Std.is(platform, MovingPlatform)
				&& (player.platform == null || (platform.velocity.y < player.platform.velocity.y)))
					player.platform = cast platform;
			}
		);
		if (player.platform == null && oldPlatform != null)
			player.onSeparatePlatform(oldPlatform);
		else if (player.platform != null && oldPlatform == null)
			player.onLandPlatform(player.platform);
		
		// Re-enable one way platforms in case other things collide
		grpOneWayPlatforms.forEach((platform)->platform.cloudSolid = true);
		
		grpTilemaps.forEach((level)->level.setTilesCollisions(40, 4, player.down ? FlxObject.NONE : FlxObject.UP));
		FlxG.collide(grpTilemaps, player);
	}
	
	inline function checkDoors()
	{
		FlxG.collide(grpLockedDoors, grpPlayers,
			function (lock:Lock, player)
			{
				if (cheeseNeededText == null)
				{
					if (cheeseCount >= lock.amountNeeded)
					{
						// Open door
						add(cheeseNeededText = lock.createText());
						cheeseNeededText.showLockAmount(()->
						{
							lock.open();
							cheeseNeededText.kill();
							cheeseNeededText = null;
							if (cheeseNeeded <= lock.amountNeeded)
								cheeseNeeded = 0;
						});
						// FlxG.sound.music.volume = 0;
					}
					else if (cheeseNeeded != lock.amountNeeded)
					{
						// replace current goal with door's goal
						add(cheeseNeededText = lock.createText());
						cheeseNeededText.animateTo
							( cheeseCountText.x + cheeseCountText.width
							, cheeseCountText.y + cheeseCountText.height / 2
							,   ()->
								{
									cheeseNeeded = lock.amountNeeded;
									cheeseNeededText.kill();
									cheeseNeededText = null;
									FlxFlicker.flicker(cheeseCountText, 1, 0.12);
								}
							);
					}
				}
			}
		);
	}
	
	inline function updateTriggers()
	{
		FlxG.overlap(grpPlayers, grpMusicTriggers, function(_, trigger:MusicTrigger)
		{
			if (musicName != trigger.daSong)
			{
				if (FlxG.sound.music != null)
					FlxG.sound.music.fadeOut(3, 0, (_)->playMusic(trigger.daSong));
				else
					playMusic(trigger.daSong);
			}
		});
		
		FlxG.overlap(grpPlayers, grpSecretTriggers, function(_, trigger:SecretTrigger)
		{
			if (!trigger.hasTriggered)
			{
				if (trigger.medal != null)
					NGio.unlockMedal(trigger.medal);
				
				trigger.hasTriggered = true;
				var oldVol:Float = FlxG.sound.music.volume;
				FlxG.sound.music.volume = 0.1;
				FlxG.sound.play('assets/sounds/discoverysound' + BootState.soundEXT, 1, false, null, true, function()
					{
						FlxG.sound.music.volume = oldVol;
					});
			}
		});
	}
	
	
	inline function checkPlayerState(player:Player)
	{
		if (player.state == Alive)
		{
			if (player.x > FlxG.worldBounds.width)
			{
				player.state = Won;
				FlxG.camera.fade(FlxColor.BLACK, 2, false, FlxG.switchState.bind(new EndState()));
			}
			
			if (SpikeObstacle.overlap(grpSpikes, player))
				player.state = Hurt;
			
			FlxG.overlap(grpCameraTiles, player, 
				(cameraTiles:CameraTilemap, _)->
				{
					playerCameras[player].leading = cameraTiles.getTileTypeAt(player.x, player.y);
				}
			);
		}
		
		if (player.state == Hurt)
			player.hurtAndRespawn(curCheckpoint.x, curCheckpoint.y - 16);
		
		dialogueBubble.visible = false;
		if (player.state == Alive)
		{
			if (player.onGround)
				FlxG.overlap(grpCheckpoint, player, handleCheckpoint);
			
			collectCheese();
		}
	}
	
	function handleCheckpoint(checkpoint:Checkpoint, player:Player)
	{
		var autoTalk = checkpoint.autoTalk;
		var dialogue = checkpoint.dialogue;
		if (!gaveCheese && player.cheese.length > 0)
		{
			gaveCheese = true;
			autoTalk = true;
			dialogue = FIRST_CHEESE_MSG + dialogue;
		}
		
		dialogueBubble.visible = true;
		dialogueBubble.setPosition(checkpoint.x + 20, checkpoint.y - 10);
		minimap.showCheckpointGet(checkpoint.ID);
		
		if (Inputs.justPressed.TALK || autoTalk)
		{
			checkpoint.onTalk();
			persistentUpdate = true;
			persistentDraw = true;
			player.state = Talking;
			var oldZoom = FlxG.camera.zoom;
			var subState = new DialogueSubstate(dialogue, false);
			subState.closeCallback = ()->
			{
				persistentUpdate = false;
				persistentDraw = false;
				final tweenTime = 0.3;
				FlxTween.tween(FlxG.camera, { zoom: oldZoom }, tweenTime, { onComplete: (_)->player.state = Alive } );
				if (checkpoint.cameraOffsetX != 0)
					FlxTween.tween(FlxG.camera.targetOffset, { x:0 }, tweenTime);
			};
			openSubState(subState);
			final tweenTime = 0.25;
			FlxTween.tween(FlxG.camera, { zoom: oldZoom * 2 }, tweenTime, {onComplete:(_)->subState.start() });
			if (checkpoint.cameraOffsetX != 0)
				FlxTween.tween(FlxG.camera.targetOffset, { x:checkpoint.cameraOffsetX }, tweenTime);
		}
		
		if (checkpoint != curCheckpoint)
		{
			curCheckpoint.deactivate();
			checkpoint.activate();
			curCheckpoint = checkpoint;
			FlxG.sound.play('assets/sounds/checkpoint' + BootState.soundEXT, 0.8);
		}
		
		if (!player.cheese.isEmpty())
		{
			player.cheese.first().sendToCheckpoint(checkpoint,
				(cheese)->
				{
					cheeseCount++;
					minimap.showCheeseGet(cheese.ID);
				}
			);
			player.cheese.clear();
		}
	}
	
	function collectCheese()
	{
		FlxG.overlap(grpPlayers, grpCheese, function(player:Player, cheese:Cheese)
		{
			FlxG.sound.play('assets/sounds/collectCheese' + BootState.soundEXT, 0.6);
			cheese.startFollow(player);
			player.cheese.add(cheese);
			NGio.unlockMedal(58879);
		});
		
		if (cheeseCount >= totalCheese)
			NGio.unlockMedal(58884);
	}
	
	inline function updateDebugFeatures()
	{
		if (FlxG.keys.justPressed.B)
			FlxG.debugger.drawDebug = !FlxG.debugger.drawDebug;
		
		if (FlxG.keys.justPressed.T)
			cheeseCount++;
	}
	
	function onPlayerRespawn():Void
	{
		// Reset moving platform
		for (i in 0...grpPlatforms.members.length)
		{
			if (grpPlatforms.members[i] != null && grpPlatforms.members[i].trigger != Load)
				grpPlatforms.members[i].resetTrigger();
		}
	}
	
	private function playMusic(name:String):Void
	{
		FlxG.sound.playMusic('assets/music/' + name + BootState.soundEXT, 0.7);
		switch (name)
		{
			case "pillow":
				FlxG.sound.music.loopTime = 4450;
				BeatGame.beatsPerMinute = 110;
			case "ritz":
				FlxG.sound.music.loopTime = 0;
				BeatGame.beatsPerMinute = 60;//not needed
		}
		musicName = name;
	}
}