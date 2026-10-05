"""Original accessory props and actual pulley-to-handle cable paths."""
import bpy
from mathutils import Vector
import equipment as e


def short_bar(width=.8):
    root=bpy.data.objects.new("Setflow straight cable handle",None)
    bpy.context.scene.collection.objects.link(root)
    root["surface_check_shaft"] = True
    steel=e.material("Equipment brushed steel",(.21,.21,.21),.75)
    e.cylinder("Cable handle shaft",.016,width,steel,root)
    return root


def create(exercise_id,rig):
    if exercise_id in ("hammer_curl","front_raise","rear_delt_raise","reverse_fly"):
        return {label:e.dumbbell(label) for label in ("l","r")}
    if exercise_id=="reverse_curl":
        return {"bar":e.barbell()}
    props={"bar":short_bar(1.1 if exercise_id=="latpull" else .8)}
    steel=e.material("Cable machine frame",(.24,.24,.24),.65)
    pad=e.material("Cable machine padding",(.04,.04,.04))
    scale=rig.scale.x
    pulley=Vector((0,-.8,2.18 if exercise_id in ("triceps_pushdown","latpull") else .16))*scale
    if exercise_id=="seated_cable_row": pulley=Vector((0,-1.15,.16))*scale
    e.cube("Cable machine column",(0,pulley.y+.16,1.16),( .09,.09,2.3),steel)
    e.cube("Cable machine base",(0,pulley.y+.16,.03),(.8,.46,.06),steel)
    e.cube("Cable machine weight stack",(.36,pulley.y+.16,.43),(.18,.25,.8),pad)
    wheel=e.cylinder("Cable machine pulley",.045,.03,steel)
    wheel.location=pulley
    if exercise_id in ("latpull","seated_cable_row"):
        y=.26 if exercise_id=="seated_cable_row" else 0
        e.cube("Cable machine seat",(0,y*scale,.39*scale),(.40,.44,.085),pad)
        e.cube("Cable machine seat support",(0,y*scale,.20),(.08,.08,.4),steel)
        if exercise_id=="latpull":
            e.cube("Lat pulldown thigh restraint",(0,-.19*scale,.53*scale),(.57,.18,.08),pad)
            e.cube("Lat pulldown overhead arm",(0,pulley.y+.2,2.18*scale),(.08,.5,.08),steel)
        else:
            for side in (-1,1):
                e.cube("Row foot brace "+str(side),(side*.22*scale,-.49*scale,.016),(.23,.33,.032),steel)
    curve=bpy.data.curves.new("Setflow moving cable","CURVE")
    curve.dimensions="3D"
    curve.bevel_depth=.004
    curve.bevel_resolution=2
    spline=curve.splines.new("POLY")
    spline.points.add(1)
    cable=bpy.data.objects.new("Cable path from pulley to handle",curve)
    bpy.context.scene.collection.objects.link(cable)
    curve.materials.append(e.material("Cable black",(.025,.025,.025)))
    cable["pulley"]=list(pulley)
    props["cable"]=cable
    return props


def apply(props,contacts,rig,frame):
    e.apply(props,contacts,rig,frame)
    if "cable" in props:
        cable=props["cable"]
        for index,point in enumerate((Vector(cable["pulley"]),props["bar"].location)):
            cable.data.splines[0].points[index].co=(*point,1)
            cable.data.splines[0].points[index].keyframe_insert("co",frame=frame)
