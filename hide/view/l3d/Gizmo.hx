package hide.view.l3d;
import h3d.scene.Object;
import hxd.Math;
import hxd.Key as K;

typedef AxesOptions = {
	?x: Bool,
	?y: Bool,
	?z: Bool
}

enum EditMode {
	Translation;
	Rotation;
	Scaling;
}

enum TransformMode {
	MoveX;
	MoveY;
	MoveZ;
	MoveXY;
	MoveYZ;
	MoveZX;
	RotateX;
	RotateY;
	RotateZ;
	Scale;
}

class ChangingStepViewer extends h3d.scene.Object {
	var textObject : h2d.ObjectFollower;
	var lifeTime : Float = 1.3;
	var life : Float = 0.;
	var text : h2d.Text;

	public function new( parentGizmo : Gizmo, stepText : String ) {
		super(parentGizmo);
		name = "ChangingStepViewer";
		textObject = new h2d.ObjectFollower(parentGizmo, @:privateAccess parentGizmo.scene.s2d);

		text = new h2d.Text(hxd.res.DefaultFont.get(), textObject);
		text.textAlign = Center;
		text.dropShadow = { dx : 0.5, dy : 0.5, color : 0x202020, alpha : 1.0 };
		text.setScale(2);
		text.setPosition(text.x + 100, text.y);
		text.text = stepText;
	}

	override function sync( ctx : h3d.scene.RenderContext ) {
		var dt = hxd.Timer.tmod * 1. / 60;
		life += dt;
		textObject.alpha = 1-life/lifeTime;
		text.y -= 20*dt*life/lifeTime;
		if (life >= lifeTime) {
			textObject.remove();
			remove();
		}
		super.sync(ctx);
	}
}

class Gizmo extends h3d.scene.Object {

	var gizmo: h3d.scene.Object;
	var deltaTextObject : h2d.ObjectFollower;
	var scene : hide.comp.Scene;
	var updateFunc: Float -> Void;
	var mouseX(get,never) : Float;
	var mouseY(get,never) : Float;
	var mouseLock(get, set) : Bool;

	public var onStartMove: TransformMode -> Void;
	public var onMove: h3d.Vector -> h3d.Quat -> h3d.Vector -> Void;
	public var onFinishMove: Void -> Void;
	public var moving(default, null): Bool;

	public var editMode : EditMode = Translation;
	public var moveStep = 0.5;
	public var snapToGrid = false;
	public var rotateStepFine = 15.0;
	public var rotateStepCoarse = 45.0;
	public var rotateSnap = false;

	var debug: h3d.scene.Graphics;
	var axisScale = false;
	var snapGround = false;
	var intOverlay : h2d.Interactive;

	public function new(scene: hide.comp.Scene) {
		super(scene.s3d);
		this.scene = scene;
		var path = hide.Ide.inst.appPath + "/res/gizmo.hmd";
		var data = sys.io.File.getBytes(path);
		var hmd = hxd.res.Any.fromBytes(path, data).toModel().toHmd();
		gizmo = hmd.makeObject();
		addChild(gizmo);
		debug = new h3d.scene.Graphics(scene.s3d);

		function setup(objname, color, mode: TransformMode) {
			var o = gizmo.getObjectByName(objname);
			var hit = gizmo.getObjectByName(objname + "_hit");
			if(hit == null) {
				hit = o;
			}
			else {
				hit.visible = false;
			}

			var mat = o.getMaterials()[0];
			mat.props = h3d.mat.MaterialSetup.current.getDefaults("ui");
			mat.mainPass.blend(SrcAlpha, OneMinusSrcAlpha);
			mat.mainPass.depth(false, Always);
			mat.mainPass.setPassName("ui");
			var mesh = hit.getMeshes()[0];
			var interactive = new h3d.scene.Interactive(mesh.primitive.getCollider(), o);
			interactive.priority = 100;
			var highlight = hxd.Math.colorLerp(color, 0xffffff, 0.1);
			color = hxd.Math.colorLerp(color, 0x000000, 0.2);
			color = (color & 0x00ffffff) | 0x80000000;
			mat.color.setColor(color);
			interactive.onOver = function(e : hxd.Event) {
				mat.color.setColor(highlight);
				mat.color.w = 1.0;
			}
			interactive.onOut = function(e : hxd.Event) {
				mat.color.setColor(color);
			}
			interactive.onPush = function(e) {
				var startPt = new h2d.col.Point(mouseX, mouseY);
				updateFunc = function(dt) {
					var mousePt = new h2d.col.Point(mouseX, mouseY);
					if(mousePt.distance(startPt) > 5) {
						startMove(mode);
					}
				}
			}
			interactive.onRelease = function(e) {
				if(moving)
					finishMove();
				else
					updateFunc = null;
			}
		}

		setup("xAxis", 0xff0000, MoveX);
		setup("yAxis", 0x00ff00, MoveY);
		setup("zAxis", 0x0000ff, MoveZ);
		setup("xy", 0xffff00, MoveXY);
		setup("xz", 0xffff00, MoveZX);
		setup("yz", 0xffff00, MoveYZ);
		setup("xRotate", 0xff0000, RotateX);
		setup("yRotate", 0x00ff00, RotateY);
		setup("zRotate", 0x0000ff, RotateZ);
		setup("scale", 0xffffff, Scale);
		translationMode();
	}

	public dynamic function onChangeMode(mode : EditMode) {}

	public function translationMode() {
		editMode = Translation;
		axisScale = false;
		for(n in ["xAxis", "yAxis", "zAxis", "xy", "xz", "yz"]) {
			gizmo.getObjectByName(n).visible = true;
		}
		for(n in ["xRotate", "yRotate", "zRotate", "scale"]) {
			gizmo.getObjectByName(n).visible = false;
		}
		onChangeMode(editMode);
	}

	public function rotationMode() {
		editMode = Rotation;
		axisScale = false;
		for(n in ["xRotate", "yRotate", "zRotate", ]) {
			gizmo.getObjectByName(n).visible = true;
		}
		for(n in ["xAxis", "yAxis", "zAxis", "xy", "xz", "yz", "scale"]) {
			gizmo.getObjectByName(n).visible = false;
		}
		onChangeMode(editMode);
	}

	public function scalingMode() {
		editMode = Scaling;
		axisScale = true;
		for(n in ["xAxis", "yAxis", "zAxis", "scale"]) {
			gizmo.getObjectByName(n).visible = true;
		}
		for(n in ["xRotate", "yRotate", "zRotate", "xy", "xz", "yz"]) {
			gizmo.getObjectByName(n).visible = false;
		}
		onChangeMode(editMode);
	}

	public function toggleSnap() {
		switch (editMode) {
			case Translation:
				snapToGrid = !snapToGrid;
			case Rotation:
				rotateSnap = !rotateSnap;
			case Scaling:
		}
	}

	public function startMove(mode: TransformMode, ?duplicating=false) {
		if (mode == Scale || (axisScale && (mode == MoveX || mode == MoveY || mode == MoveZ)))
			mouseLock = true;
		moving = true;
		if(onStartMove != null) onStartMove(mode);
		var startMat = getAbsPos().clone();
		var startQuat = new h3d.Quat();
		startQuat.initRotateMatrix(startMat);
		var startPos = getAbsPos().getPosition().toPoint();
		var dragPlane = null;
		var cam = scene.s3d.camera;
		var norm = startPos.sub(cam.pos.toPoint());
		intOverlay = new h2d.Interactive(40000, 40000, scene.s2d);
		intOverlay.onPush = function(e) finishMove();
		switch(mode) {
			case MoveXY: norm.set(0, 0, 1);
			case MoveYZ: norm.set(1, 0, 0);
			case MoveZX: norm.set(0, 1, 0);
			case RotateX: norm.set(1, 0, 0);
			case RotateY: norm.set(0, 1, 0);
			case RotateZ: norm.set(0, 0, 1);
			default:
		}

		var moveSteps : Array<Float> = scene.editor.view.config.get("sceneeditor.gridSnapSteps");
		var rotateSteps : Array<Float> = scene.editor.view.config.get("sceneeditor.rotateStepCoarses");
		var rotateStepFineIndex = rotateSteps.indexOf(rotateStepFine);

		if (mode == MoveX || mode == MoveY || mode == MoveZ || mode == Scale) {
			var point = scene.s3d.camera.rayFromScreen(mouseX, mouseY).getDir();
			dragPlane = h3d.col.Plane.fromNormalPoint(point, startPos);
		} else {
			norm.normalize();
			norm.transform3x3(startMat);
			dragPlane = h3d.col.Plane.fromNormalPoint(norm, startPos);
		}
		var startDragPt = getDragPoint(dragPlane);
		var cursor = new h3d.scene.Object();
		deltaTextObject = new h2d.ObjectFollower(cursor, scene.s2d);

		var tx = new h2d.Text(hxd.res.DefaultFont.get(), deltaTextObject);
		tx.textColor = 0xff0000;
		tx.textAlign = Center;
		tx.dropShadow = { dx : 0.5, dy : 0.5, color : 0x202020, alpha : 1.0 };
		tx.setScale(1.2);
		var ty = new h2d.Text(hxd.res.DefaultFont.get(), deltaTextObject);
		ty.textColor = 0x00ff00;
		ty.textAlign = Center;
		ty.dropShadow = { dx : 0.5, dy : 0.5, color : 0x202020, alpha : 1.0 };
		ty.setScale(1.2);
		var tz = new h2d.Text(hxd.res.DefaultFont.get(), deltaTextObject);
		tz.textColor = 0x0000ff;
		tz.textAlign = Center;
		tz.dropShadow = { dx : 0.5, dy : 0.5, color : 0x202020, alpha : 1.0 };
		tz.setScale(1.2);
		updateFunc = function(dt) {
			tx.visible = false;
			ty.visible = false;
			tz.visible = false;
			var curPt = getDragPoint(dragPlane);
			tx.setPosition(mouseX + 32, mouseY - 15);
			ty.setPosition(mouseX + 32, mouseY);
			tz.setPosition(mouseX + 32, mouseY + 15);
			var delta = curPt.sub(startDragPt);
			var vec = new h3d.Vector(0,0,0);
			var quat = new h3d.Quat();
			var speedFactor = (K.isDown(K.SHIFT) && !K.isDown(K.CTRL)) ? 0.1 : 1.0;
			delta.scale(speedFactor);
			inline function scaleFunc(x: Float) {
				return x > 0 ? x + 1 : 1 / (1 - x);
			}

			function moveSnap(m: Float) {
				if(moveStep <= 0 || !snapToGrid || axisScale)
					return m;

				var step = K.isDown(K.SHIFT) ? moveStep / 2.0 : moveStep;
				return hxd.Math.round(m / step) * step;
			}
			if (mode == MoveX || mode == MoveY || mode == MoveZ || mode == MoveXY || mode == MoveYZ || mode == MoveZX) {
				if ( snapToGrid && K.isPressed(K.SHIFT) ) {
					scene.editor.updateGrid(moveSteps[(moveSteps.indexOf(moveStep) + 1 ) % moveSteps.length]);
					var changingStepViewer = new ChangingStepViewer(this, "" + moveStep);
				}
			}
			if(mode == MoveX || mode == MoveXY || mode == MoveZX) vec.x = moveSnap(delta.dot(startMat.front().toPoint()));
			if(mode == MoveY || mode == MoveYZ || mode == MoveXY) vec.y = moveSnap(delta.dot(startMat.right().toPoint()));
			if(mode == MoveZ || mode == MoveZX || mode == MoveYZ) vec.z = moveSnap(delta.dot(startMat.up().toPoint()));

			if(!axisScale) {
				vec.transform3x3(startMat);
				if (vec.x != 0) {
					tx.visible = true;
					tx.text = "X : "+ Math.round(vec.x*100)/100.;
				}
				if (vec.y != 0) {
					ty.visible = true;
					ty.text = "Y : "+ Math.round(vec.y*100)/100.;
				}
				if (vec.z != 0) {
					tz.visible = true;
					tz.text = "Z : "+ Math.round(vec.z*100)/100.;
				}
				x = (startPos.x + vec.x);
				y = (startPos.y + vec.y);
				z = (startPos.z + vec.z);
			}

			if(mode == Scale) {
				var scale = scaleFunc(delta.z * 0.5);
				vec.set(scale, scale, scale);
			}

			if(mode == RotateX || mode == RotateY || mode == RotateZ) {
				var v1 = startDragPt.sub(startPos);
				v1.normalize();
				var v2 = curPt.sub(startPos);
				v2.normalize();

				var angle = Math.atan2(v1.cross(v2).dot(norm), v1.dot(v2)) * speedFactor;
				if(rotateSnap || K.isDown(K.CTRL)) {
					if (K.isPressed(K.CTRL)) {
						rotateStepCoarse = rotateSteps[rotateSteps.indexOf(rotateStepFine)];
						var changingStepViewer = new ChangingStepViewer(this, "" + rotateStepCoarse + "°");
					}
					if (K.isPressed(K.SHIFT)) {
						rotateStepCoarse = rotateSteps[rotateStepFineIndex];
						rotateStepFineIndex = (rotateStepFineIndex + 1) % rotateSteps.length;
						var changingStepViewer = new ChangingStepViewer(this, "" + rotateStepCoarse + "°");
					}
					var step = hxd.Math.degToRad(rotateStepCoarse);
					angle =  hxd.Math.round(angle / step) * step;
				}
				if (mode == RotateX && angle != 0) {
					tx.visible = true;
					tx.text = ""+ Math.round(Math.radToDeg(angle)*100)/100. + "°";
				}
				if (mode == RotateY && angle != 0) {
					ty.visible = true;
					ty.text = ""+ Math.round(Math.radToDeg(angle)*100)/100. + "°";
				}
				if (mode == RotateZ && angle != 0) {
					tz.visible = true;
					tz.text = ""+ Math.round(Math.radToDeg(angle)*100)/100. + "°";
				}
				quat.initRotateAxis(norm.x, norm.y, norm.z, angle);
				var localQuat = new h3d.Quat();
				localQuat.multiply(quat, startQuat);
				setRotationQuat(localQuat);
			}

			if(onMove != null) {
				if(axisScale && mode != Scale) {
					vec.x = scaleFunc(vec.x);
					vec.y = scaleFunc(vec.y);
					vec.z = scaleFunc(vec.z);
					if (vec.x != 1) {
						tx.visible = true;
						tx.text = ""+ Math.round(vec.x*100)/100.;
					}
					if (vec.y != 1) {
						ty.visible = true;
						ty.text = ""+ Math.round(vec.y*100)/100.;
					}
					if (vec.z != 1) {
						tz.visible = true;
						tz.text = ""+ Math.round(vec.z*100)/100.;
					}
					onMove(null, null, vec);
				}
				else {
					if(mode == Scale) {
						if (vec.x != 1) {
							tx.visible = true;
							tx.text = ""+ Math.round(vec.x*100)/100.;
						}
						if (vec.y != 1) {
							ty.visible = true;
							ty.text = ""+ Math.round(vec.y*100)/100.;
						}
						if (vec.z != 1) {
							tz.visible = true;
							tz.text = ""+ Math.round(vec.z*100)/100.;
						}
						onMove(null, null, vec);
					}
					else
						onMove(vec, quat, null);
				}
			}

			if(duplicating && K.isPressed(K.MOUSE_LEFT) || K.isPressed(K.ESCAPE) || (!duplicating && !K.isDown(K.MOUSE_LEFT))) {
				finishMove();
			}
		}
	}

	function get_mouseX() return @:privateAccess scene.window.mouseX;
	function get_mouseY() return @:privateAccess scene.window.mouseY;
	function get_mouseLock() return @:privateAccess scene.window.mouseMode != Absolute;
	function set_mouseLock(v : Bool) {
		@:privateAccess scene.window.mouseMode = v ? AbsoluteUnbound(true) : Absolute;
		return v;
	}

	function finishMove() {
		deltaTextObject.remove();
		mouseLock = false;
		updateFunc = null;
		if(onFinishMove != null)
			onFinishMove();
		posChanged = true;
		moving = false;
		if(intOverlay != null) {
			intOverlay.remove();
			intOverlay = null;
		}
	}

	function getDragPoint(plane: h3d.col.Plane) {
		var cam = scene.s3d.camera;
		var ray = cam.rayFromScreen(mouseX, mouseY);
		return ray.intersect(plane);
	}

	public function update(dt) {
		var cam = this.getScene().camera;
		var gpos = gizmo.getAbsPos().getPosition();
		var distToCam = cam.pos.sub(gpos).length();
		var engine = h3d.Engine.getCurrent();
		var ratio = 150 / engine.height;
		gizmo.setScale(ratio * distToCam * Math.tan(cam.fovY * 0.5 * Math.PI / 180.0));

		if( !moving ) {
			var dir = cam.pos.sub(gpos).toPoint();
			dir = gizmo.globalToLocal(dir);
			gizmo.getObjectByName("xAxis").setRotation(0, 0, dir.x < 0 ? Math.PI : 0);
			gizmo.getObjectByName("yAxis").setRotation(0, 0, dir.y < 0 ? Math.PI : 0);
			gizmo.getObjectByName("zAxis").setRotation(dir.z < 0 ? Math.PI : 0, 0, 0);
			gizmo.getObjectByName("xy").setRotation(0, 0, dir.x < 0 ? dir.y < 0 ? Math.PI : Math.PI / 2.0 : dir.y < 0 ? -Math.PI / 2.0 : 0);
			gizmo.getObjectByName("xz").setRotation(0, dir.z < 0 ? dir.x < 0 ? Math.PI : Math.PI / 2.0 : 0, dir.x < 0 ? dir.z < 0 ? 0 : Math.PI : 0);
			gizmo.getObjectByName("yz").setRotation(dir.z < 0 ? dir.y < 0 ? Math.PI : -Math.PI / 2.0 : 0, 0, dir.y < 0 ? dir.z < 0 ? 0 : Math.PI : 0);
			gizmo.getObjectByName("xRotate").setRotation(dir.z < 0 ? -Math.PI / 2.0 : 0, 0, dir.y < 0 ? Math.PI : 0);
			gizmo.getObjectByName("yRotate").setRotation(0, dir.z < 0 ? Math.PI / 2.0 : 0, dir.x < 0 ? Math.PI : 0);
			gizmo.getObjectByName("zRotate").setRotation(0, 0, dir.x < 0 ? dir.y < 0 ? Math.PI : Math.PI / 2.0 : dir.y < 0 ? -Math.PI / 2.0 : 0);
		}

		//axisScale = K.isDown(K.ALT);
		// for(n in ["xRotate", "yRotate", "zRotate", "xy", "xz", "yz", "scale"]) {
		// 	gizmo.getObjectByName(n).visible = !axisScale;
		// }

		if(updateFunc != null) {
			updateFunc(dt);
		}
	}
}