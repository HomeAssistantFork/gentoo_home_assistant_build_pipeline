// Middle selector gearbox concept
// - Bottom-left and bottom-right gears removed
// - One free-spinning middle selector gear engages left OR right gear by arm position
// - Servo is moved away from gearbox face so horn can couple to the selector arm
// - All key features include print clearances

$fn = 80;

// ---------- Print/process tolerances ----------
print_gap = 0.28;          // radial/linear running gap for FDM
axial_gap = 0.35;          // Z gap so parts do not fuse
peg_clearance = 0.30;      // shaft hole oversize
retainer_snap_gap = 0.20;  // gap under retainer disks

// ---------- Gear parameters ----------
pressure_angle = 20;
gear_thickness = 6;
module_size = 1.35;
backlash = 0.14;
root_clearance = 0.25;

left_teeth = 30;
right_teeth = 30;
selector_teeth = 16;

// Distance from selector to each side gear.
selector_mesh_c = ((selector_teeth + left_teeth) * module_size / 2) + print_gap;

// Selector arm pivot position. Selector can swing between side gears.
pivot_y = -22;
arm_len = 36;
arm_w = 8;
arm_t = 4;

// Angle state for inspection: -1 = left engage, 0 = center, 1 = right engage
engage_state = 0;
engage_angle = engage_state * 21;

// ---------- Plate / peg parameters ----------
plate_w = 132;
plate_h = 88;
plate_t = 5;
plate_corner_r = 6;

peg_d = 6.0;
peg_h = 10;
retainer_d = 13;
retainer_t = 1.6;

// ---------- Servo envelope ----------
servo_w = 40;
servo_h = 20;
servo_t = 38;
servo_offset_z = -14; // moved away from plate face
horn_d = 10;
horn_h = 3;

left_c = [-selector_mesh_c, 0, plate_t];
right_c = [ selector_mesh_c, 0, plate_t];
pivot_c = [0, pivot_y, plate_t];

// ---------- Involute helpers ----------
function polar(r, a) = [r * cos(a), r * sin(a)];
function involute_point(rb, t) = [rb * (cos(t) + t * sin(t)), rb * (sin(t) - t * cos(t))];
function clamp(x, lo, hi) = x < lo ? lo : (x > hi ? hi : x);

module involute_gear_2d(teeth, m=1, pa=20, backlash=0.1, clearance=0.2) {
    pitch_r = teeth * m / 2;
    base_r = pitch_r * cos(pa);
    add_r = pitch_r + m;
    root_r = max(0.8, pitch_r - (1.25 * m + clearance));

    // Tooth thickness at pitch circle with backlash reduction.
    pitch_tooth_angle = 360 / teeth;
    half_tooth_angle = (pitch_tooth_angle / 4) - (backlash / (2 * pitch_r)) * 180 / PI;

    // Involute parameter at addendum.
    t_max = sqrt(max(0, (add_r * add_r - base_r * base_r) / (base_r * base_r)));

    steps = 6;
    pts_fwd = [
        for (i = [0:steps])
            let (t = t_max * i / steps)
            involute_point(base_r, t)
    ];

    // Rotate involute so it intersects pitch circle at half tooth angle.
    t_pitch = sqrt(max(0, (pitch_r * pitch_r - base_r * base_r) / (base_r * base_r)));
    p_pitch = involute_point(base_r, t_pitch);
    inv_pitch_ang = atan(p_pitch[1], p_pitch[0]);
    rot_ang = half_tooth_angle - inv_pitch_ang;

    tooth_profile = concat(
        [[0, 0]],
        [for (p = pts_fwd) let (pr = polar(norm(p), atan(p[1], p[0]) + rot_ang)) [pr[0], pr[1]]],
        [for (i = [steps:-1:0])
            let (
                p = pts_fwd[i],
                pr = polar(norm(p), -atan(p[1], p[0]) - rot_ang)
            ) [pr[0], pr[1]]]
    );

    intersection() {
        union() {
            circle(r = root_r);

            // Add involute-like teeth around the root disk.
            for (k = [0:teeth-1]) {
                rotate(k * 360 / teeth)
                    polygon(points = tooth_profile);
            }
        }

        // Trim to addendum radius.
        circle(r = add_r);
    }
}

module spur_gear(teeth, m=1, thickness=5, bore_d=4) {
    difference() {
        linear_extrude(height = thickness)
            involute_gear_2d(teeth = teeth, m = m, pa = pressure_angle, backlash = backlash, clearance = root_clearance);
        translate([0, 0, -0.1])
            cylinder(h = thickness + 0.2, d = bore_d + peg_clearance);
    }
}

module rounded_plate(w, h, t, r) {
    linear_extrude(height = t)
        hull() {
            translate([ w/2-r,  h/2-r]) circle(r=r);
            translate([-w/2+r,  h/2-r]) circle(r=r);
            translate([ w/2-r, -h/2+r]) circle(r=r);
            translate([-w/2+r, -h/2+r]) circle(r=r);
        }
}

module peg_with_retainer(pos=[0,0,0]) {
    translate(pos)
        cylinder(h = peg_h, d = peg_d);

    // Printed retainer disk above gear stack to stop sliding off pegs.
    translate([pos[0], pos[1], pos[2] + peg_h - retainer_t])
        difference() {
            cylinder(h = retainer_t, d = retainer_d);
            translate([0,0,-0.1]) cylinder(h = retainer_t + 0.2, d = peg_d + retainer_snap_gap);
        }
}

module selector_arm() {
    rotate([0,0,engage_angle])
    union() {
        // Arm around pivot with clearance bore for free spin on pivot peg.
        difference() {
            hull() {
                translate([0, 0, 0]) cylinder(h = arm_t, d = arm_w + 8);
                translate([0, arm_len, 0]) cylinder(h = arm_t, d = arm_w + 4);
            }
            translate([0,0,-0.1]) cylinder(h = arm_t + 0.2, d = peg_d + peg_clearance + 0.25);
            translate([0,arm_len,-0.1]) cylinder(h = arm_t + 0.2, d = peg_d + peg_clearance + 0.25);
        }

        // Selector gear rides on arm tip and is free-spinning on same axis as servo spinner.
        translate([0, arm_len, arm_t + axial_gap])
            spur_gear(teeth = selector_teeth, m = module_size, thickness = gear_thickness, bore_d = peg_d);
    }
}

module servo_mount() {
    // Servo body moved away from gearbox face.
    translate([-servo_w/2, pivot_y - servo_t/2, plate_t + servo_offset_z])
        cube([servo_w, servo_t, servo_h]);

    // Simple horn aligned with pivot axis (free-spinning gear shares this axis on the arm tip).
    translate([0, pivot_y, plate_t + servo_offset_z + servo_h])
        cylinder(h = horn_h, d = horn_d);

    // Spacer standoffs from plate to servo bracket zone.
    for (sx = [-14, 14]) {
        translate([sx, pivot_y - 12, plate_t + servo_offset_z])
            cylinder(h = -servo_offset_z + 1, d = 5);
    }
}

module assembly() {
    // Base plate
    color([0.85, 0.85, 0.9])
        rounded_plate(plate_w, plate_h, plate_t, plate_corner_r);

    // Fixed pegs for side gears and pivot.
    peg_with_retainer(left_c);
    peg_with_retainer(right_c);
    peg_with_retainer(pivot_c);

    // Left and right large gears.
    color([0.95, 0.5, 0.35])
    translate([left_c[0], left_c[1], left_c[2] + axial_gap])
        rotate([0,0,8])
            spur_gear(teeth = left_teeth, m = module_size, thickness = gear_thickness, bore_d = peg_d);

    color([0.95, 0.5, 0.35])
    translate([right_c[0], right_c[1], right_c[2] + axial_gap])
        rotate([0,0,-8])
            spur_gear(teeth = right_teeth, m = module_size, thickness = gear_thickness, bore_d = peg_d);

    // Arm pivots at servo axis. Selector gear sits at arm tip.
    color([0.3, 0.35, 0.4])
    translate([pivot_c[0], pivot_c[1], pivot_c[2] + axial_gap])
        selector_arm();

    // Servo moved away from face.
    color([0.3, 0.45, 0.8, 0.6])
        servo_mount();
}

assembly();
