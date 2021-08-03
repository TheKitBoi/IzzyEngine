package;

import flixel.FlxSprite;
import flixel.addons.display.FlxTiledSprite;
import flixel.animation.FlxAnimation;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.frames.FlxFrame;
import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;
import haxe.Json;
import openfl.display.BitmapData;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;
import sys.FileSystem;
import sys.io.File;

typedef NoteStyleData =
{
	var name:String;
	var atlasPath:Array<String>;
	var globalNoteScale:Float;
	var antialiasing:Bool;
	var animPrefixes:NoteStyleAnimations;
}

typedef NoteStyleAnimations =
{
	var arrow:Array<String>;
	var tailHold:Array<String>;
	var tailEnd:Array<String>;
	var strumIdle:Array<String>;
	var strumPress:Array<String>;
	var strumHit:Array<String>;
}

class NoteStyle
{
	// Holds note assets, from arrows, strum lines, and tails.
	public static var noteAsset:FlxAtlasFrames;
	public static var data:NoteStyleData;

	// Needed for FlxTiledSprite
	public static var tailHoldGraphics:Array<FlxGraphic> = [null, null, null, null];

	public static function loadNoteStyle(file:String = "default", reload:Bool = false)
	{
		if (reload && noteAsset != null)
		{
			noteAsset.destroy();
			noteAsset = null;
		}

		if (noteAsset == null)
		{
			var path:String = "./data/noteStyles/";
			if (FileSystem.exists(path + file + ".json"))
				path += file + ".json";
			else
				path += "default.json";

			data = Json.parse(File.getContent(path));

			var atlasTexture:FlxGraphic = AssetHelper.getAsset(data.atlasPath[0] + ".png", IMAGE, data.atlasPath[1]);
			atlasTexture.persist = true;
			atlasTexture.destroyOnNoUse = false;
			noteAsset = FlxAtlasFrames.fromSparrow(atlasTexture, File.getContent(AssetHelper.getPath(data.atlasPath[0] + ".xml", IMAGE, data.atlasPath[1])));

			/* Pre-scale note holds due to how FlxTiledSprite works */
			for (frameName in noteAsset.framesHash.keys())
			{
				for (i in 0...4)
				{
					if (StringTools.startsWith(frameName, NoteStyle.data.animPrefixes.tailHold[i]))
					{
						var frame:FlxFrame = NoteStyle.noteAsset.framesHash.get(frameName);
						var graphic:FlxGraphic = FlxGraphic.fromFrame(frame);
						graphic.persist = true;
						graphic.destroyOnNoUse = false;

						// Scale the BitmapData inside the graphic
						var matrix:Matrix = new Matrix();
						matrix.scale(data.globalNoteScale, data.globalNoteScale);
						var newBD:BitmapData = new BitmapData(Std.int(graphic.bitmap.width * data.globalNoteScale),
							Std.int(graphic.bitmap.height * data.globalNoteScale), true, 0x000000);
						newBD.draw(graphic.bitmap, matrix, null, null, null, NoteStyle.data.antialiasing);
						graphic.bitmap = newBD;

						if (tailHoldGraphics[i] != null)
							tailHoldGraphics[i].destroy();

						tailHoldGraphics[i] = graphic;
					}
				}
			}
		}
	}
}

class NoteObject extends FlxTypedSpriteGroup<FlxSprite>
{
	public var strumIndex:Int;
	public var time:Float;
	public var holdTime:Float;
	public var holdProgress:Float = 0.0;
	public var noteSpeed:Float = 1.0;

	public var arrow:FlxSprite;
	public var tailHold:FlxTiledSprite;
	public var tailEnd:FlxSprite;
	public var noteScale:Float;

	var prevNoteSpeed:Float = 0.0;

	public function new(x:Float, y:Float, strumIndex:Int, time:Float, holdTime:Float = 0.0, noteSpeed:Float = 1.0, scale:Float = 1.0)
	{
		super(x, y);

		this.strumIndex = strumIndex;
		this.time = time;
		this.holdTime = holdTime;
		this.noteSpeed = noteSpeed;
		this.noteScale = scale;

		// Just in case it's not loaded yet
		NoteStyle.loadNoteStyle();

		// Tail (note hold) rendering
		if (holdTime > 0)
		{
			tailHold = new FlxTiledSprite(null, NoteStyle.tailHoldGraphics[strumIndex].width, 10);
			tailHold.loadGraphic(NoteStyle.tailHoldGraphics[strumIndex]);
			tailHold.origin.set();
			tailHold.antialiasing = NoteStyle.data.antialiasing;
			add(tailHold);

			tailEnd = new FlxSprite();
			tailEnd.frames = NoteStyle.noteAsset;
			tailEnd.antialiasing = NoteStyle.data.antialiasing;
			tailEnd.animation.addByPrefix("idle", NoteStyle.data.animPrefixes.tailEnd[strumIndex], 0, false);
			tailEnd.animation.play("idle");
			tailEnd.origin.set();
			tailEnd.scale.x = NoteStyle.data.globalNoteScale * noteScale;
			tailEnd.scale.y = tailEnd.scale.x;
			tailEnd.updateHitbox();
			add(tailEnd);
		}

		// Arrow rendering
		arrow = new FlxSprite(0, 0);
		arrow.frames = NoteStyle.noteAsset;
		arrow.antialiasing = NoteStyle.data.antialiasing;
		arrow.animation.addByPrefix("idle", NoteStyle.data.animPrefixes.arrow[strumIndex], 0, false);
		arrow.animation.play("idle");
		arrow.origin.set();
		arrow.scale.x = NoteStyle.data.globalNoteScale * noteScale;
		arrow.scale.y = arrow.scale.x;
		arrow.updateHitbox();

		if (tailHold != null)
			tailHold.x = (arrow.width - tailHold.width) / 2;

		updateNoteHold();

		add(arrow);
	}

	public function updateNoteHold()
	{
		if (prevNoteSpeed != noteSpeed || holdProgress > 0)
		{
			if (tailHold != null)
			{
				if (holdProgress > holdTime)
					holdProgress = holdTime;

				/* This is where I ran out of variable names */
				var th:Float = (holdTime * (400.0 * noteSpeed));
				var tp:Float = (holdProgress * (400.0 * noteSpeed));

				tailHold.height = th - tp;
				tailHold.y = 10 + arrow.y + tp;
				tailHold.scrollY = -tp;
				tailEnd.setPosition(tailHold.x, 10 + arrow.y + th);

				// trace("hp " + holdProgress + " tp " + tp + " normal " + holdTime + " y " + arrow.y);
			}

			prevNoteSpeed = noteSpeed;
		}
	}
}

class StrumLine extends FlxTypedSpriteGroup<FlxTypedSpriteGroup<FlxSprite>>
{
	public var noteSpeed:Float;
	public var time:Float;

	var strumLineScale:Float;

	var strumObjects:Array<FlxSprite> = [];
	var noteObjects:Array<NoteObject> = [];

	public function new(x:Float, y:Float, scale:Float = 1.0, noteSpeed:Float = 1.0)
	{
		super(x, y);

		this.strumLineScale = scale;
		this.noteSpeed = noteSpeed;

		// Just in case it's not loaded yet
		NoteStyle.loadNoteStyle();

		for (i in 0...4)
		{
			var strumPart:FlxTypedSpriteGroup<FlxSprite> = new FlxTypedSpriteGroup<FlxSprite>((i * (108 * strumLineScale)), 0);
			add(strumPart);

			var strum:FlxSprite = new FlxSprite();
			strum.frames = NoteStyle.noteAsset;
			strum.antialiasing = NoteStyle.data.antialiasing;

			strum.animation.addByPrefix("idle", NoteStyle.data.animPrefixes.strumIdle[i], 0, false);
			strum.animation.addByPrefix("pressed", NoteStyle.data.animPrefixes.strumPress[i], 24, false);
			strum.animation.addByPrefix("hit", NoteStyle.data.animPrefixes.strumHit[i], 24, false);
			strum.animation.play("idle");

			strum.updateHitbox();
			strum.origin.set();
			strum.scale.x = NoteStyle.data.globalNoteScale * strumLineScale;
			strum.scale.y = strum.scale.x;
			strumPart.add(strum);

			strumObjects.push(strum);
		}
	}

	override public function update(elapsed:Float)
	{
		super.update(elapsed);

		for (note in noteObjects)
		{
			// Calculate note time relative to current song time
			var timeRel:Float = note.time - time;

			// Used for note hold rendering
			note.noteSpeed = noteSpeed;
			note.updateNoteHold();

			// Update note position
			note.y = (timeRel * (400.0 * noteSpeed)) + y;

			// Unhide note when it's on the screen
			if (!note.visible)
			{
				if (note.y < 720)
					note.visible = true;
			}
		}
	}

	/* Helper function to play animation on a specific strum line sprite */
	inline public function playStrumAnim(strumIndex:Int, animName:String)
		strumObjects[strumIndex].animation.play(animName);

	inline public function getCurrentStrumAnim(strumIndex:Int):FlxAnimation
		return strumObjects[strumIndex].animation.curAnim;

	public function addNote(strumIndex:Int, time:Float, holdTime:Float = 0.0)
	{
		if (strumIndex < 4)
		{
			var note:NoteObject = new NoteObject(0, 0, strumIndex, time, holdTime, noteSpeed);
			// Hide note to minimize rendering cost
			note.visible = false;
			members[strumIndex].add(note);
			// Store in a separate array for easy access
			noteObjects.push(note);
		}
	}

	public function getNote(strumIndex:Int, time:Float):NoteObject
	{
		for (note in noteObjects)
		{
			if (note.strumIndex == strumIndex && note.time == time)
			{
				return note;
			}
		}

		return null;
	}

	public function invalidateNote(strumIndex:Int, time:Float)
	{
		var note:NoteObject = getNote(strumIndex, time);

		if (note != null)
		{
			note.alpha = 0.2;
			if (note.tailHold != null)
			{
				var clonedBD:BitmapData = note.tailHold.graphic.bitmap.clone();
				var clonedFG:FlxGraphic = FlxGraphic.fromBitmapData(clonedBD);

				clonedBD.colorTransform(clonedBD.rect, new ColorTransform(1, 1, 1, 0.2));
				note.tailHold.graphic = clonedFG;
			}
		}
	}

	public function removeNote(strumIndex:Int, time:Float)
	{
		var note:NoteObject = getNote(strumIndex, time);
		if (note != null)
		{
			remove(note, true);
			noteObjects.remove(note);
			note.destroy();
		}
	}
}
