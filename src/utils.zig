// Scales v from the input range to the output range. This is useful for all
// kinds of transitions. E.g. to move an image in from the right side of the
// screen to the center over 2 second, starting at the 3 second:
// x = scale(time, 3, 5, screen_size.x, screen_size.x/2)
pub fn scale(val: anytype, in_min: anytype, in_max: anytype, out_min: anytype, out_max: anytype) @TypeOf(val, in_min, in_max) {
    const _in_min = in_min;
    const _out_min = out_min;
    return _out_min + ((out_max) - _out_min) * (((val) - _in_min) / ((in_max) - _in_min));
}
