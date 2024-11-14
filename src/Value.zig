const std = @import("std");
const Object = @import("Object.zig");

const Self = @This();

const q_nan: u64 = 0x7ffc000000000000;

const mask_tag: u64 = 0x000000000000000003;
const mask_payload: u64 = 0x0003fffffffffffffc;

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

pub fn isNil(self: Self) bool {
    return self.raw == nil.raw;
}

pub fn isBool(self: Self) bool {
    return !self.isFloat() and !self.isObject() and (self.raw & mask_tag == tag_true or self.raw & mask_tag == tag_false);
}

pub fn isInt(self: Self) bool {
    return !self.isFloat() and !self.isObject() and self.raw & mask_tag == tag_int;
}

pub fn isFloat(self: Self) bool {
    return (self.raw & q_nan) != q_nan;
}

pub fn isObject(self: Self) bool {
    return !self.isFloat() and self.raw & tag_object == tag_object;
}

pub fn toBool(self: Self) ?bool {
    if (!self.isBool()) return null;
    return self.raw & tag_true == tag_true;
}

pub fn toInt(self: Self) ?i48 {
    if (!self.isInt()) return null;
    return @truncate(@as(i64, @bitCast((self.raw ^ q_nan) >> 2)));
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
pub fn eq(self: Self, other: Self) ?Self {
    return initBool(self.isEqual(other));
}
pub fn neq(self: Self, other: Self) ?Self {
    return initBool(!self.isEqual(other));
}
pub fn lt(self: Self, other: Self) ?Self {
    return self.intBinaryOp(other, intLt);
}
pub fn le(self: Self, other: Self) ?Self {
    return self.intBinaryOp(other, intLe);
}
pub fn gt(self: Self, other: Self) ?Self {
    return self.intBinaryOp(other, intGt);
}
pub fn ge(self: Self, other: Self) ?Self {
    return self.intBinaryOp(other, intGe);
}
pub fn logAnd(self: Self, other: Self) ?Self {
    return boolBinaryOp(self, other, boolAnd);
}
pub fn logOr(self: Self, other: Self) ?Self {
    return boolBinaryOp(self, other, boolOr);
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
pub fn shl(self: Self, other: Self) ?Self {
    return self.intBinaryOp(other, intShiftLeft);
}
pub fn shr(self: Self, other: Self) ?Self {
    return self.intBinaryOp(other, intShiftRight);
}
pub fn pos(self: Self) ?Self {
    return self.intOrFloatUnaryOp(initInt, initFloat);
}
pub fn neg(self: Self) ?Self {
    return self.intOrFloatUnaryOp(intNeg, floatNeg);
}
pub fn bitNot(self: Self) ?Self {
    return self.intUnaryOp(intBitNot);
}
pub fn logNot(self: Self) ?Self {
    return self.boolUnaryOp(boolNot);
}

fn intOrFloatBinaryOp(self: Self, other: Self, intOp: fn (i48, i48) Self, floatOp: fn (f64, f64) Self) ?Self {
    if (self.isInt() and other.isInt()) {
        return intOp(self.toInt().?, other.toInt().?);
    } else if (self.isFloat() and other.isFloat()) {
        return floatOp(self.toFloat().?, other.toFloat().?);
    } else if (self.isInt() and other.isFloat()) {
        return floatOp(@as(f64, @floatFromInt(self.toInt().?)), other.toFloat().?);
    } else if (self.isFloat() and other.isInt()) {
        return floatOp(self.toFloat().?, @as(f64, @floatFromInt(other.toInt().?)));
    } else {
        return null;
    }
}

fn intBinaryOp(self: Self, other: Self, op: fn (i48, i48) Self) ?Self {
    if (self.isInt() and other.isInt()) {
        return op(self.toInt().?, other.toInt().?);
    } else {
        return null;
    }
}

fn boolBinaryOp(self: Self, other: Self, op: fn (bool, bool) Self) ?Self {
    if (self.isBool() and other.isBool()) {
        return op(self.toBool().?, other.toBool().?);
    } else {
        return null;
    }
}

fn intOrFloatUnaryOp(self: Self, intOp: fn (i48) Self, floatOp: fn (f64) Self) ?Self {
    if (self.isInt()) {
        return intOp(self.toInt().?);
    } else if (self.isFloat()) {
        return floatOp(self.toFloat().?);
    } else {
        return null;
    }
}

fn intUnaryOp(self: Self, op: fn (i48) Self) ?Self {
    if (self.isInt()) {
        return op(self.toInt().?);
    } else {
        return null;
    }
}

fn boolUnaryOp(self: Self, op: fn (bool) Self) ?Self {
    if (self.isBool()) {
        return op(self.toBool().?);
    } else {
        return null;
    }
}

fn intAdd(left: i48, right: i48) Self {
    return initInt(left + right);
}
fn intSub(left: i48, right: i48) Self {
    return initInt(left - right);
}
fn intMul(left: i48, right: i48) Self {
    return initInt(left * right); // FIXME: should cast to float on overflow
}
fn intDiv(left: i48, right: i48) Self {
    return initInt(@divTrunc(left, right));
}
fn intMod(left: i48, right: i48) Self {
    return initInt(@rem(left, right)); // FIXME: check for right < 0
}
fn intBitAnd(left: i48, right: i48) Self {
    return initInt(left & right);
}
fn intBitOr(left: i48, right: i48) Self {
    return initInt(left | right);
}
fn intBitXor(left: i48, right: i48) Self {
    return initInt(left ^ right);
}
fn intShiftLeft(left: i48, right: i48) Self {
    return initInt(left << @intCast(right)); // FIXME: check for right > max u6
}
fn intShiftRight(left: i48, right: i48) Self {
    return initInt(left >> @intCast(right)); // FIXME: check for right > max u6
}
fn intLt(left: i48, right: i48) Self {
    return initBool(left < right);
}
fn intLe(left: i48, right: i48) Self {
    return initBool(left <= right);
}
fn intGt(left: i48, right: i48) Self {
    return initBool(left > right);
}
fn intGe(left: i48, right: i48) Self {
    return initBool(left >= right);
}
fn intNeg(int: i48) Self {
    return initInt(-int);
}
fn intBitNot(int: i48) Self {
    return initInt(~int);
}

fn floatAdd(left: f64, right: f64) Self {
    return initFloat(left + right);
}
fn floatSub(left: f64, right: f64) Self {
    return initFloat(left - right);
}
fn floatMul(left: f64, right: f64) Self {
    return initFloat(left * right);
}
fn floatDiv(left: f64, right: f64) Self {
    return initFloat(left / right);
}
fn floatNeg(float: f64) Self {
    return initFloat(-float);
}

fn boolAnd(left: bool, right: bool) Self {
    return initBool(left and right);
}
fn boolOr(left: bool, right: bool) Self {
    return initBool(left or right);
}
fn boolNot(b: bool) Self {
    return initBool(!b);
}

fn isEqual(self: Self, other: Self) bool {
    return self.raw == other.raw;
}

pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;

    if (self.isNil()) {
        return writer.writeAll("nil");
    } else if (self.isBool()) {
        return writer.writeAll(if (self.toBool().?) "true" else "false");
    } else if (self.isInt()) {
        return writer.print("{d}", .{self.toInt().?});
    } else if (self.isFloat()) {
        return writer.print("{d}", .{self.toFloat().?});
    } else {
        unreachable;
    }
}
