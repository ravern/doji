const std = @import("std");
const Object = @import("Object.zig");

const Self = @This();

const q_nan: u64 = 0x7ffc000000000000;

const tag_nil: usize = 0x0000000000000000;
const tag_true: usize = 0x0000000000000001;
const tag_false: usize = 0x0000000000000002;
const tag_int: usize = 0x0000000000000003;
const tag_object: usize = 0x8000000000000000;

pub const nil = Self{ .raw = q_nan | tag_nil };

raw: u64,

pub fn initBool(b: bool) Self {
    return Self{ .raw = q_nan | (if (b) tag_true else tag_false) };
}

pub fn initInt(int: i48) Self {
    return Self{ .raw = @as(u64, q_nan | tag_int | @as(u64, @bitCast(@as(i64, @intCast(int)) << 2))) };
}

pub fn initFloat(float: f64) Self {
    return Self{ .raw = @bitCast(float) };
}

pub fn isInt(self: Self) bool {
    return !self.isFloat() and !self.isObject() and self.raw & tag_int == tag_int;
}

pub fn isFloat(self: Self) bool {
    return (self.raw & q_nan) != q_nan;
}

pub fn isObject(self: Self) bool {
    return !self.isFloat() and self.raw & tag_object == tag_object;
}

pub fn toInt(self: Self) ?i48 {
    if (!self.isInt()) return null;
    return @intCast(@as(i64, @bitCast((self.raw ^ q_nan) >> 2)));
}

pub fn toFloat(self: Self) ?f64 {
    if (!self.isFloat()) return null;
    return @bitCast(self.raw);
}

// primitive operations

pub fn add(self: Self, other: Self) ?Self {
    return self.intOrFloatBinaryOp(other, intAdd, floatAdd);
}
pub fn sub(self: Self, other: Self) ?Self {
    return self.intOrFloatBinaryOp(other, intSub, floatSub);
}
pub fn mul(self: Self, other: Self) ?Self {
    return self.intOrFloatBinaryOp(other, intMul, floatMul);
}
pub fn div(self: Self, other: Self) ?Self {
    return self.intOrFloatBinaryOp(other, intDiv, floatDiv);
}
pub fn mod(self: Self, other: Self) ?Self {
    return self.intBinaryOp(other, intMod);
}
pub fn bitAnd(self: Self, other: Self) ?Self {
    return self.intBinaryOp(other, intBitAnd);
}
pub fn bitOr(self: Self, other: Self) ?Self {
    return self.intBinaryOp(other, intBitOr);
}
pub fn bitXor(self: Self, other: Self) ?Self {
    return self.intBinaryOp(other, intBitXor);
}
pub fn shiftLeft(self: Self, other: Self) ?Self {
    return self.intBinaryOp(other, intShiftLeft);
}
pub fn shiftRight(self: Self, other: Self) ?Self {
    return self.intBinaryOp(other, intShiftRight);
}
pub fn neg(self: Self) ?Self {
    return self.intUnaryOp(intNeg);
}
pub fn bitNot(self: Self) ?Self {
    return self.intUnaryOp(intBitNot);
}

fn intOrFloatBinaryOp(self: Self, other: Self, intOp: fn (i48, i48) i48, floatOp: fn (f64, f64) f64) ?Self {
    if (self.isInt() and other.isInt()) {
        return initInt(@intCast(intOp(self.toInt().?, other.toInt().?)));
    } else if (self.isFloat() and other.isFloat()) {
        return initFloat(floatOp(self.toFloat().?, other.toFloat().?));
    } else if (self.isInt() and other.isFloat()) {
        return initFloat(floatOp(@as(f64, @floatFromInt(self.toInt().?)), other.toFloat().?));
    } else if (self.isFloat() and other.isInt()) {
        return initFloat(floatOp(self.toFloat().?, @as(f64, @floatFromInt(other.toInt().?))));
    } else {
        return null;
    }
}

fn intBinaryOp(self: Self, other: Self, op: fn (i48, i48) i48) ?Self {
    if (self.isInt() and other.isInt()) {
        return initInt(op(self.toInt().?, other.toInt().?));
    } else {
        return null;
    }
}

fn intUnaryOp(self: Self, op: fn (i48) i48) ?Self {
    if (self.isInt()) {
        return initInt(op(self.toInt().?));
    } else {
        return null;
    }
}

fn intAdd(left: i48, right: i48) i48 {
    return left + right;
}
fn intSub(left: i48, right: i48) i48 {
    return left - right;
}
fn intMul(left: i48, right: i48) i48 {
    return left * right; // FIXME: should cast to float on overflow
}
fn intDiv(left: i48, right: i48) i48 {
    return @divTrunc(left, right);
}
fn intMod(left: i48, right: i48) i48 {
    return @rem(left, right); // FIXME: check for right < 0
}
fn intBitAnd(left: i48, right: i48) i48 {
    return left & right;
}
fn intBitOr(left: i48, right: i48) i48 {
    return left | right;
}
fn intBitXor(left: i48, right: i48) i48 {
    return left ^ right;
}
fn intShiftLeft(left: i48, right: i48) i48 {
    return left << @intCast(right); // FIXME: check for right > max u6
}
fn intShiftRight(left: i48, right: i48) i48 {
    return left >> @intCast(right); // FIXME: check for right > max u6
}
fn intNeg(int: i48) i48 {
    return -int;
}
fn intBitNot(int: i48) i48 {
    return ~int;
}

fn floatAdd(left: f64, right: f64) f64 {
    return left + right;
}
fn floatSub(left: f64, right: f64) f64 {
    return left - right;
}
fn floatMul(left: f64, right: f64) f64 {
    return left * right;
}
fn floatDiv(left: f64, right: f64) f64 {
    return left / right;
}

pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;

    if (self.isInt()) {
        return writer.print("{d}", .{self.toInt().?});
    } else if (self.isFloat()) {
        return writer.print("{d}", .{self.toFloat().?});
    } else {
        unreachable;
    }
}
