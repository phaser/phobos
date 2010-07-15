// Written in the D programming language.

/**
This module defines a few useful _range incarnations. Credit for ideas
in building this module go to $(WEB fantascienza.net/leonardo/so/,
Leonardo Maffi).

Macros:

WIKI = Phobos/StdRange

Copyright: Copyright Andrei Alexandrescu 2008-.
License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors:   $(WEB erdani.org, Andrei Alexandrescu)
*/
module std.range;

public import std.array;
import std.exception;
import std.traits;
import std.typecons;
import std.typetuple;
import std.algorithm;
import std.functional;
import std.conv;

// For testing only.  This code is included in a string literal to be included
// in whatever module it's needed in, so that each module that uses it can be
// tested individually, without needing to link to std.range.
enum dummyRanges = q{
    // Used with the dummy ranges for testing higher order ranges.
    enum RangeType {
        Input,
        Forward,
        Bidirectional,
        Random
    }

    enum Length {
        Yes,
        No
    }

    enum ReturnBy {
        Reference,
        Value
    }

    // Range that's useful for testing other higher order ranges,
    // can be parametrized with attributes.  It just dumbs down an array of
    // numbers 1..10.
    struct DummyRange(ReturnBy _r, Length _l, RangeType _rt) {
        // These enums are so that the template params are visible outside
        // this instantiation.
        enum r = _r;
        enum l = _l;
        enum rt = _rt;

        uint[] arr = [1U, 2U, 3U, 4U, 5U, 6U, 7U, 8U, 9U, 10U];

        void reinit() {
            // Workaround for DMD bug 4378
            arr = [1U, 2U, 3U, 4U, 5U, 6U, 7U, 8U, 9U, 10U];
        }

        void popFront() {
            arr = arr[1..$];
        }

        @property bool empty() {
            return arr.length == 0;
        }

        static if(r == ReturnBy.Reference) {
            @property ref uint front() {
                return arr[0];
            }
        } else {
            @property uint front() {
                return arr[0];
            }
        }

        static if(rt >= RangeType.Forward) {
            @property typeof(this) save() {
                return this;
            }
        }

        static if(rt >= RangeType.Bidirectional) {
            void popBack() {
                arr = arr[0..$ - 1];
            }

            static if(r == ReturnBy.Reference) {
                @property ref uint back() {
                    return arr[$ - 1];
                }
            } else {
                @property uint back() {
                    return arr[$ - 1];
                }
            }
        }

        static if(rt >= RangeType.Random) {
            static if(r == ReturnBy.Reference) {
                @property ref uint opIndex(size_t index) {
                    return arr[index];
                }
            } else {
                @property uint opIndex(size_t index) {
                    return arr[index];
                }
            }
        }

        static if(l == Length.Yes) {
            @property size_t length() {
                return arr.length;
            }
        }
    }

    enum dummyLength = 10;

    alias TypeTuple!(
        DummyRange!(ReturnBy.Reference, Length.Yes, RangeType.Input),
        DummyRange!(ReturnBy.Reference, Length.Yes, RangeType.Forward),
        DummyRange!(ReturnBy.Reference, Length.Yes, RangeType.Bidirectional),
        DummyRange!(ReturnBy.Reference, Length.Yes, RangeType.Random),
        DummyRange!(ReturnBy.Reference, Length.No, RangeType.Input),
        DummyRange!(ReturnBy.Reference, Length.No, RangeType.Forward),
        DummyRange!(ReturnBy.Reference, Length.No, RangeType.Bidirectional),
        DummyRange!(ReturnBy.Value, Length.Yes, RangeType.Input),
        DummyRange!(ReturnBy.Value, Length.Yes, RangeType.Forward),
        DummyRange!(ReturnBy.Value, Length.Yes, RangeType.Bidirectional),
        DummyRange!(ReturnBy.Value, Length.Yes, RangeType.Random),
        DummyRange!(ReturnBy.Value, Length.No, RangeType.Input),
        DummyRange!(ReturnBy.Value, Length.No, RangeType.Forward),
        DummyRange!(ReturnBy.Value, Length.No, RangeType.Bidirectional)
    ) AllDummyRanges;

    alias TypeTuple!(1,2,3,4,5,6,7,8,9,0,11,12,13,14,15,16) DummyIndices;
};

version(unittest)
{
    import std.container, std.conv, std.math, std.stdio;

    mixin(dummyRanges);

    // Tests whether forward, bidirectional and random access properties are
    // propagated properly from the base range(s) R to the higher order range
    // H.  Useful in combination with DummyRange for testing several higher
    // order ranges.
    template propagatesRangeType(H, R...) {
        static if(allSatisfy!(isRandomAccessRange, R)) {
           enum bool propagatesRangeType = isRandomAccessRange!H;
        } else static if(allSatisfy!(isBidirectionalRange, R)) {
            enum bool propagatesRangeType = isBidirectionalRange!H;
        } else static if(allSatisfy!(isForwardRange, R)) {
            enum bool propagatesRangeType = isForwardRange!H;
        } else {
            enum bool propagatesRangeType = isInputRange!H;
        }
    }

    template propagatesLength(H, R...) {
        static if(allSatisfy!(hasLength, R)) {
            enum bool propagatesLength = hasLength!H;
        } else {
            enum bool propagatesLength = !hasLength!H;
        }
    }
}

/**
Returns $(D true) if $(D R) is an input range. An input range must
define the primitives $(D empty), $(D popFront), and $(D front). The
following code should compile for any input range.

----
R r;             // can define a range object
if (r.empty) {}  // can test for empty
r.popFront;          // can invoke next
auto h = r.front; // can get the front of the range
----

The semantics of an input range (not checkable during compilation) are
assumed to be the following ($(D r) is an object of type $(D R)):

$(UL $(LI $(D r.empty) returns $(D false) iff there is more data
available in the range.)  $(LI $(D r.front) returns the current element
in the range. It may return by value or by reference. Calling $(D
r.front) is allowed only if calling $(D r.empty) has, or would have,
returned $(D false).) $(LI $(D r.popFront) advances to the popFront element in
the range. Calling $(D r.popFront) is allowed only if calling $(D r.empty)
has, or would have, returned $(D false).))
 */
template isInputRange(R)
{
    enum bool isInputRange = is(typeof(
    {
        R r;             // can define a range object
        if (r.empty) {}  // can test for empty
        r.popFront;          // can invoke next
        auto h = r.front; // can get the front of the range
    }()));
}

unittest
{
    struct A {}
    static assert(!isInputRange!(A));
    struct B
    {
        void popFront();
        bool empty();
        int front();
    }
    static assert(isInputRange!(B));
    static assert(isInputRange!(int[]));
    static assert(isInputRange!(char[]));
}

/**
Returns $(D true) if $(D R) is an output range. An output range must
define the primitive $(D put) that accepts an object of type $(D
E). The following code should compile for any output range.

----
R r;             // can define a range object
E e;
r.put(e);        // can write an element to the range
----
The semantics of an output range (not checkable during compilation)
are assumed to be the following ($(D r) is an object of type $(D R)):

$(UL $(LI $(D r.put(e)) puts $(D e) in the range (in a range-dependent
manner) and advances to the popFront position in the range. Successive
calls to $(D r.put) add elements to the range. $(D put) may throw to
signal failure.))
 */
template isOutputRange(R, E)
{
    enum bool isOutputRange = is(typeof(
    {
        R r;            // can define a range object
        E e;
        r.put(e);       // can write element to range
    }()));
}

unittest
{
    struct A {}
    static assert(!isInputRange!(A));
    struct B
    {
        void put(int);
    }
    static assert(isOutputRange!(B, int));
    static assert(isOutputRange!(int[], int));
}

/**
Returns $(D true) if $(D R) is a forward range. A forward range is an
input range that can save "checkpoints" by simply copying it to
another value of the same type. Notable examples of input ranges that
are $(I not) forward ranges are file/socket ranges; copying such a
range will not save the position in the stream, and they most likely
reuse an internal buffer as the entire stream does not sit in
memory. Subsequently, advancing either the original or the copy will
advance the stream, so the copies are not independent. The following
code should compile for any forward range.

----
static assert(isInputRange!(R));
R r1;
R r2 = r1;           // can copy a range to another
----

The semantics of a forward range (not checkable during compilation)
are the same as for an input range, with the additional requirement
that backtracking must be possible by saving a copy of the range
object.
 */
template isForwardRange(R)
{
    enum bool isForwardRange = isInputRange!(R) && is(typeof(
    {
        R r1;
        R r2 = r1.save;           // can call "save" against a range
                                  // object
    }()));
}

unittest
{
    static assert(!isForwardRange!(int));
    static assert(isForwardRange!(int[]));
}

/**
Returns $(D true) if $(D R) is a bidirectional range. A bidirectional
range is a forward range that also offers the primitives $(D back) and
$(D popBack). The following code should compile for any bidirectional
range.

----
R r;
static assert(isForwardRange!(R)); // range is an input range
r.popBack;                        // can invoke popBack
auto t = r.back;                   // can get the back of the range
----
The semantics of a bidirectional range (not checkable during compilation)
are assumed to be the following ($(D r) is an object of type $(D R)):

$(UL $(LI $(D r.back) returns (possibly a reference to) the last
element in the range. Calling $(D r.back) is allowed only if calling
$(D r.empty) has, or would have, returned $(D false).))
 */
template isBidirectionalRange(R)
{
    enum bool isBidirectionalRange = isForwardRange!(R) && is(typeof(
    {
        R r;
        r.popBack;         // can invoke popBack
        auto h = r.back;    // can get the back of the range
    }()));
}

unittest
{
    struct A {}
    static assert(!isBidirectionalRange!(A));
    struct B
    {
        void popFront();
        bool empty();
        int front();
    }
    static assert(!isBidirectionalRange!(B));
    struct C
    {
        @property bool empty();
        @property C save();
        void popFront();
        @property int front();
        void popBack();
        @property int back();
    }
    static assert(isBidirectionalRange!(C));
    static assert(isBidirectionalRange!(int[]));
    static assert(isBidirectionalRange!(char[]));
}

/**
Returns $(D true) if $(D R) is a random-access range. A random-access
range is a forward range that also offers the primitive $(D
opIndex), OR an infinite input range that offers $(D opIndex). The
following code should compile for any random-access range.

----
R r;
static assert(isForwardRange!(R)); // range is forward
static assert(isBidirectionalRange!(R) || isInfinite!(R));
                                  // range is bidirectional or infinite
auto e = r[1];                    // can index
----

The semantics of a random-access range (not checkable during
compilation) are assumed to be the following ($(D r) is an object of
type $(D R)):
$(UL $(LI $(D r.opIndex(n)) returns a reference to the $(D n)th
element in the range.))
 */
template isRandomAccessRange(R)
{
    enum bool isRandomAccessRange =
        (isBidirectionalRange!(R) || isInfinite!(R))
        && is(typeof(R.init[1]))
        && !isNarrowString!R
        && (hasLength!R || isInfinite!R);
}

unittest
{
    struct A {}
    static assert(!isRandomAccessRange!(A));
    struct B
    {
        void popFront();
        bool empty();
        int front();
    }
    static assert(!isRandomAccessRange!(B));
    struct C
    {
        void popFront();
        bool empty();
        int front();
        void popBack();
        int back();
    }
    static assert(!isRandomAccessRange!(C));
    struct D
    {
        bool empty();
        @property D save();
        int front();
        void popFront();
        int back();
        void popBack();
        ref int opIndex(uint);
        @property size_t length();
        //int opSlice(uint, uint);
    }
    static assert(isRandomAccessRange!(D));
    static assert(isRandomAccessRange!(int[]));
}

/**
The element type of $(D R). $(D R) does not have to be a range. The
element type is determined as the type yielded by $(D r.front) for an
object $(D r) or type $(D R). For example, $(D ElementType!(T[])) is
$(D T).
 */
template ElementType(R)
{
    //alias typeof({ R r; return front(r[]); }()) ElementType;
    static if (is(typeof(R.front()) T))
        alias T ElementType;
    else
        alias void ElementType;
}

unittest
{
    enum XYZ : string { a = "foo" };
    auto x = front(XYZ.a);
    static assert(is(ElementType!(XYZ) : dchar));
    immutable char[3] a = "abc";
    static assert(is(ElementType!(typeof(a)) : dchar));
    int[] i;
    static assert(is(ElementType!(typeof(i)) : int));
}

/**
Returns $(D true) if $(D R) is a forward range and has swappable
elements. The following code should compile for any random-access
range.

----
R r;
static assert(isForwardRange!(R));  // range is forward
swap(r.front, r.front);              // can swap elements of the range
----
 */
template hasSwappableElements(R)
{
    enum bool hasSwappableElements = isForwardRange!(R) && is(typeof(
    {
        R r;
        swap(r.front, r.front);             // can swap elements of the range
    }()));
}

unittest
{
    static assert(!hasSwappableElements!(const int[]));
    static assert(!hasSwappableElements!(const(int)[]));
    static assert(hasSwappableElements!(int[]));
    //static assert(hasSwappableElements!(char[]));
}

/**
Returns $(D true) if $(D R) is a forward range and has mutable
elements. The following code should compile for any random-access
range.

----
R r;
static assert(isForwardRange!(R));  // range is forward
auto e = r.front;
r.front = e;                         // can assign elements of the range
----
 */
template hasAssignableElements(R)
{
    enum bool hasAssignableElements = isForwardRange!(R) && is(typeof(
    {
        R r;
        static assert(isForwardRange!(R)); // range is forward
        auto e = r.front;
        r.front = e;                       // can assign elements of the range
    }()));
}

unittest
{
    static assert(!hasAssignableElements!(const int[]));
    static assert(!hasAssignableElements!(const(int)[]));
    static assert(hasAssignableElements!(int[]));
}

/**
Returns $(D true) if $(D R) has a $(D length) member that returns an
integral type. $(D R) does not have to be a range. Note that $(D
length) is an optional primitive as no range must implement it. Some
ranges do not store their length explicitly, some cannot compute it
without actually exhausting the range (e.g. socket streams), and some
other ranges may be infinite.
 */
template hasLength(R)
{
    enum bool hasLength = is(typeof(R.init.length) : ulong) &&
        !isNarrowString!R;
}

unittest
{
    static assert(hasLength!(int[]));
    struct A { ulong length; }
    static assert(hasLength!(A));
    struct B { size_t length() { return 0; } }
    static assert(!hasLength!(B));
    struct C { @property size_t length() { return 0; } }
    static assert(hasLength!(C));
}

/**
Returns $(D true) if $(D Range) is an infinite input range. An
infinite input range is an input range that has a statically-defined
enumerated member called $(D empty) that is always $(D false), for
example:

----
struct InfiniteRange
{
    enum bool empty = false;
    ...
}
----
 */

template isInfinite(Range)
{
    static if (isInputRange!Range && is(char[1 + Range.empty]))
        enum bool isInfinite = !Range.empty;
    else
        enum bool isInfinite = false;
}

unittest
{
    assert(!isInfinite!(int[]));
    assert(isInfinite!(Repeat!(int)));
}

/**
Returns $(D true) if $(D Range) offers a slicing operator with
integral boundaries, that in turn returns an input range type. The
following code should compile for $(D hasSlicing) to be $(D true):

----
Range r;
auto s = r[1 .. 2];
static assert(isInputRange!(typeof(s)));
----
 */
template hasSlicing(Range)
{
    enum bool hasSlicing = is(typeof(
    {
        Range r;
        auto s = r[1 .. 2];
        static assert(isInputRange!(typeof(s)));
    }()));
}

unittest
{
    static assert(hasSlicing!(int[]));
    struct A { int opSlice(uint, uint); }
    static assert(!hasSlicing!(A));
    struct B { int[] opSlice(uint, uint); }
    static assert(hasSlicing!(B));
}

/**
This is a best-effort implementation of $(D length) for any kind of
range.

If $(D hasLength!(Range)), simply returns $(D range.length) without
checking $(D upTo).

Otherwise, walks the range through its length and returns the number
of elements seen. Performes $(BIGOH n) evaluations of $(D range.empty)
and $(D range.popFront), where $(D n) is the effective length of $(D
range). The $(D upTo) parameter is useful to "cut the losses" in case
the interest is in seeing whether the range has at least some number
of elements. If the parameter $(D upTo) is specified, stops if $(D
upTo) steps have been taken and returns $(D upTo).
 */
size_t walkLength(Range)(Range range, size_t upTo = size_t.max)
if (isInputRange!(Range))
{
    static if (isRandomAccessRange!Range && hasLength!Range)
    {
        return range.length;
    }
    else
    {
        size_t result;
        for (; result < upTo && !range.empty; range.popFront) ++result;
        return result;
    }
}

unittest
{
    int[] a = [ 1, 2, 3 ];
    assert(walkLength(a) == 3);
    assert(walkLength(a, 0) == 3);
}

private template isRetro(R)
{
    static if (is(R R1 == Retro!R2, R2))
    {
        enum isRetro = true;
    }
    else
    {
        enum isRetro = false;
    }
}

/**
Iterates a bidirectional range backwards.

Example:
----
int[] a = [ 1, 2, 3, 4, 5 ];
assert(equal(retro(a) == [ 5, 4, 3, 2, 1 ][]));
----
 */
struct Retro(R) if (isBidirectionalRange!(R) && !isRetro!R)
{
private:
    R _input;
    enum bool byRef = is(typeof(&(R.init.front())));

public:
    alias R Source;

/**
Forwards to $(D _input.empty).
 */
    @property bool empty()
    {
        return _input.empty;
    }

/**
Returns a copy of $(D this).
 */
    @property Retro save()
    {
        return Retro(_input.save);
    }

/**
Forwards to $(D _input.popBack).
 */
    void popFront()
    {
        _input.popBack;
    }

/**
Forwards to $(D _input.popFront).
 */
    void popBack()
    {
        _input.popFront;
    }

/// @@@UGLY@@@
/**
Forwards to $(D _input.back).
 */
    mixin(
        (byRef ? "ref " : "")~
        q{ElementType!(R) front()
            {
                return _input.back;
            }
        });

/**
Forwards to $(D _input.front).
 */
    mixin(
        (byRef ? "ref " : "")~
        q{ElementType!(R) back()
            {
                return _input.front;
            }
        });
/**
Forwards to $(D _input[_input.length - n + 1]). Defined only if $(D R)
is a random access range and if $(D R) defines $(D R.length).
 */
    static if (isRandomAccessRange!(R) && hasLength!(R))
        static if (byRef)
            auto ref ElementType!R opIndex(uint n)
            {
                return _input[_input.length - n - 1];
            }
        else
            ElementType!R opIndex(uint n)
            {
                return _input[_input.length - n - 1];
            }

/**
Range primitive operation that returns the length of the
range. Forwards to $(D _input.length) and is defined only if $(D
hasLength!(R)).
 */
    static if (hasLength!R || isNarrowString!R)
        @property size_t length()
        {
            return _input.length;
        }
}

template Retro(R) if (isRetro!R)
{
    alias R.Source Retro;
}

/// Ditto
Retro!(R) retro(R)(R input) if (isBidirectionalRange!(R))
{
    static if (isRetro!R)
        return input._input;
    else
        return Retro!(R)(input);
}

unittest
{
    int[] a;
    static assert(is(typeof(a) == typeof(retro(retro(a)))));
    static assert(isRandomAccessRange!(Retro!(int[])));
    void test(int[] input, int[] witness)
    {
        auto r = retro(input);
        assert(r.front == witness.front);
        assert(r.back == witness.back);
        assert(equal(r, witness));
    }
    test([ 1 ], [ 1 ]);
    test([ 1, 2 ], [ 2, 1 ]);
    test([ 1, 2, 3 ], [ 3, 2, 1 ]);
    test([ 1, 2, 3, 4 ], [ 4, 3, 2, 1 ]);
    test([ 1, 2, 3, 4, 5 ], [ 5, 4, 3, 2, 1 ]);
    test([ 1, 2, 3, 4, 5, 6 ], [ 6, 5, 4, 3, 2, 1 ]);

    foreach(DummyType; AllDummyRanges) {
        static if(!isBidirectionalRange!DummyType) {
            static assert(!__traits(compiles, Retro!DummyType));
        } else {
            DummyType dummyRange;
            dummyRange.reinit();

            auto myRetro = retro(dummyRange);
            static assert(propagatesRangeType!(typeof(myRetro), DummyType));
            assert(myRetro.front == 10);
            assert(myRetro.back == 1);

            static if(isRandomAccessRange!DummyType && hasLength!DummyType) {
                assert(myRetro[0] == myRetro.front);

                static if(DummyType.r == ReturnBy.Reference) {
                    myRetro[9]++;
                    assert(dummyRange[0] == 2);
                    myRetro.front++;
                    assert(myRetro.front == 11);
                    myRetro.back++;
                    assert(myRetro.back == 3);
                }
            }
        }
    }
}

/**
Iterates range $(D r) with stride $(D n). If the range is a
random-access range, moves by indexing into the range; otehrwise,
moves by successive calls to $(D popFront).

Example:
----
int[] a = [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 ];
assert(equal(stride(a, 3) == [ 1, 4, 7, 10 ][]));
----
 */
struct Stride(R) if (isInputRange!(R))
{
private:
    R _input;
    size_t _n;

public:
/**
Initializes the stride.
 */
    this(R input, size_t n)
    {
        _input = input;
        _n = n;
        static if (hasLength!(R))
        {
            auto slack = _input.length % _n;
            if (slack) slack--;
            if (!slack) return;
            static if (isRandomAccessRange!(R) && hasSlicing!(R))
            {
                _input = _input[0 .. _input.length - slack];
            }
            else static if(isBidirectionalRange!(R))
            {
                foreach (i; 0 .. slack)
                {
                    if (_input.empty) break;
                    _input.popBack;
                }
            }
        }
    }

/**
Returns $(D this).
 */
    static if(isForwardRange!(R))
    {
        @property Stride save()
        {
            return Stride(_input.save, _n);
        }
    }

/**
Forwards to $(D _input.empty).
 */
    @property bool empty()
    {
        return _input.empty;
    }

/**
@@@
 */
    void popFront()
    {
        static if (isRandomAccessRange!(R) && hasLength!(R) && hasSlicing!(R))
        {
            _input = _input[
                _n < _input.length ? _n : _input.length
                .. _input.length];
        }
        else
            foreach (i; 0 .. _n)
            {
                _input.popFront;
                if (_input.empty) break;
            }
    }

/**
Forwards to $(D _input.popFront).
 */
    static if (isBidirectionalRange!(R) && hasLength!(R))
        void popBack()
        {
            enforce(_input.length >= _n);
            static if (isRandomAccessRange!(R) && hasSlicing!(R))
            {
                _input = _input[0 .. _input.length - _n];
            }
            else
            {
                foreach (i; 0 .. _n)
                {
                    if (_input.empty) break;
                    _input.popBack;
                }
            }
        }

/**
Forwards to $(D _input.front).
 */
    @property ref ElementType!(R) front()
    {
        return _input.front;
    }

/**
Forwards to $(D _input.back) after getting rid of any slack items.
 */
    static if(isBidirectionalRange!(R) && hasLength!(R))
    {
        @property ref ElementType!(R) back()
        {
            return _input.back;
        }
    }

/**
Forwards to $(D _input[_input.length - n + 1]). Defined only if $(D R)
is a random access range and if $(D R) defines $(D R.length).
 */
    static if (isRandomAccessRange!(R) && hasLength!(R))
        ref ElementType!(R) opIndex(uint n)
        {
            return _input[_n * n];
        }

/**
Range primitive operation that returns the length of the
range. Forwards to $(D _input.length) and is defined only if $(D
hasLength!(R)).
 */
    static if (hasLength!(R))
        @property size_t length()
        {
            return (_input.length + _n - 1) / _n;
        }
}

/// Ditto
Stride!(R) stride(R)(R input, size_t n)
    if (isInputRange!(R))
{
    enforce(n > 0);
    return Stride!(R)(input, n);
}

unittest
{
    static assert(isRandomAccessRange!(Stride!(int[])));
    void test(size_t n, int[] input, int[] witness)
    {
        assert(equal(stride(input, n), witness));
    }
    test(1, [], []);
    int[] arr = [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    test(1, arr, arr);
    test(2, arr, [1, 3, 5, 7, 9]);
    test(3, arr, [1, 4, 7, 10]);
    test(4, arr, [1, 5, 9]);

    foreach(DummyType; AllDummyRanges) {
        static if(DummyType.r == ReturnBy.Reference) {
            // Doesn't work yet w/o ref returns, see DMD bug 3294 and 3894.
            DummyType dummyRange;
            dummyRange.reinit();

            auto myStride = stride(dummyRange, 4);

            // Should fail if no length and bidirectional b/c there's no way
            // to know how much slack we have.
            static if(hasLength!DummyType || !isBidirectionalRange!DummyType) {
                static assert(propagatesRangeType!(typeof(myStride), DummyType));
            }
            assert(myStride.front == 1);
            assert(equal(myStride, [1, 5, 9]));

            static if(hasLength!DummyType) {
                assert(myStride.length == 3);
            }

            static if(isBidirectionalRange!DummyType && hasLength!DummyType) {
                assert(myStride.back == 9);
            }

            static if(isRandomAccessRange!DummyType && hasLength!DummyType) {
                assert(myStride[0] == 1);
                assert(myStride[1] == 5);
                assert(myStride[2] == 9);
            }
        }
    }
}

/**
Spans multiple ranges in sequence. The function $(D chain) takes any
number of ranges and returns a $(D Chain!(R1, R2,...)) object. The
ranges may be different, but they must have the same element type. The
result is a range that offers the $(D front), $(D popFront), and $(D empty)
primitives. If all input ranges offer random access and $(D length),
$(D Chain) offers them as well.

If only one range is offered to $(D Chain) or $(D chain), the $(D Chain)
type exits the picture by aliasing itself directly to that range's
type.

Example:
----
int[] arr1 = [ 1, 2, 3, 4 ];
int[] arr2 = [ 5, 6 ];
int[] arr3 = [ 7 ];
auto s = chain(arr1, arr2, arr3);
assert(s.length == 7);
assert(s[5] == 6);
assert(equal(s, [1, 2, 3, 4, 5, 6, 7][]));
----
 */

template Chain(R...) if (allSatisfy!(isInputRange, R))
{
    static if (R.length > 1)
        alias ChainImpl!(R) Chain;
    else
        alias R[0] Chain;
}

struct ChainImpl(R...)
{
private:
    alias CommonType!(staticMap!(.ElementType, R)) RvalueElementType;
    template sameET(A)
    {
        enum sameET = is(.ElementType!(A) == RvalueElementType);
    }
    enum bool allSameType = allSatisfy!(sameET, R);

    Tuple!(R) _input;

public:
    // This doesn't work yet
    static if (allSameType)
        alias ref RvalueElementType ElementType;
    else
        alias RvalueElementType ElementType;

    this(R input)
    {
        foreach (i, v; input)
        {
            _input.field[i] = v;
        }
    }

    @property bool empty()
    {
        foreach (i, Unused; R)
        {
            if (!_input.field[i].empty) return false;
        }
        return true;
    }

    static if (allSatisfy!(isForwardRange, R))
        ChainImpl save()
        {
            auto result = ChainImpl();
            foreach (i, Unused; R)
            {
                result._input.field[i] = _input.field[i].save;
            }
            return result;
        }

    void popFront()
    {
        foreach (i, Unused; R)
        {
            if (_input.field[i].empty) continue;
            _input.field[i].popFront;
            return;
        }
    }

    @property RvalueElementType front()
    {
        foreach (i, Unused; R)
        {
            if (_input.field[i].empty) continue;
            return _input.field[i].front;
        }
        assert(false);
    }

    static if (allSatisfy!(hasAssignableElements, R))
    {
        // @@@BUG@@@
        //@property void front(T)(T v) if (is(T : RvalueElementType))
        @property void front(RvalueElementType v)
        {
            foreach (i, Unused; R)
            {
                if (_input.field[i].empty) continue;
                _input.field[i].front = v;
                return;
            }
            assert(false);
        }
    }

    RvalueElementType moveFront()
    {
        foreach (i, Unused; R)
        {
            if (_input.field[i].empty) continue;
            return .moveFront(_input.field[i]);
        }
        assert(false);
    }

    static if (allSatisfy!(isBidirectionalRange, R))
    {
        mixin(
            ((allSameType && allSatisfy!(hasAssignableElements, R)) ? "ref " : "")~
            q{ElementType back()
                {
                    foreach_reverse (i, Unused; R)
                    {
                        if (_input.field[i].empty) continue;
                        return _input.field[i].back;
                    }
                    assert(false);
                }
            });

        void popBack()
        {
            foreach_reverse (i, Unused; R)
            {
                if (_input.field[i].empty) continue;
                _input.field[i].popBack;
                return;
            }
        }
    }

    static if (allSatisfy!(hasLength, R))
        @property size_t length()
        {
            size_t result;
            foreach (i, Unused; R)
            {
                result += _input.field[i].length;
            }
            return result;
        }

    static if (allSatisfy!(isRandomAccessRange, R))
    {
        mixin(
            ((allSameType && allSatisfy!(hasAssignableElements, R)) ? "ref " : "")~
            q{ElementType opIndex(uint index)
                {
                    foreach (i, Unused; R)
                    {
                        immutable length = _input.field[i].length;
                        if (index < length) return _input.field[i][index];
                        index -= length;
                    }
                    assert(false);
                }
            });

        static if (allSameType && allSatisfy!(hasAssignableElements, R))
        void opIndexAssign(ElementType v, uint index)
        {
            foreach (i, Unused; R)
            {
                immutable length = _input.field[i].length;
                if (index < length)
                {
                    _input.field[i][index] = v;
                    return;
                }
                index -= length;
            }
            assert(false);
        }
    }

    static if (allSatisfy!(hasLength, R) && allSatisfy!(hasSlicing, R))
        ChainImpl opSlice(size_t begin, size_t end)
        {
            auto result = this;
            foreach (i, Unused; R)
            {
                immutable len = result._input.field[i].length;
                if (len < begin)
                {
                    result._input.field[i] = result._input.field[i]
                        [len .. len];
                    begin -= len;
                }
                else
                {
                    result._input.field[i] = result._input.field[i]
                        [begin .. len];
                    break;
                }
            }
            auto cut = length;
            cut = cut <= end ? 0 : cut - end;
            foreach_reverse (i, Unused; R)
            {
                immutable len = result._input.field[i].length;
                if (cut > len)
                {
                    result._input.field[i] = result._input.field[i]
                        [0 .. 0];
                    cut -= len;
                }
                else
                {
                    result._input.field[i] = result._input.field[i]
                        [0 .. len - cut];
                    break;
                }
            }
            return result;
        }
}

/// Ditto
Chain!(R) chain(R...)(R input)
{
    static if (input.length > 1)
        return Chain!(R)(input);
    else
        return input[0];
}

unittest
{
    {
        int[] arr1 = [ 1, 2, 3, 4 ];
        int[] arr2 = [ 5, 6 ];
        int[] arr3 = [ 7 ];
        int[] witness = [ 1, 2, 3, 4, 5, 6, 7 ];
        auto s1 = chain(arr1);
        static assert(isRandomAccessRange!(typeof(s1)));
        auto s2 = chain(arr1, arr2);
        static assert(isBidirectionalRange!(typeof(s2)));
        static assert(isRandomAccessRange!(typeof(s2)));
        s2.front = 1;
        auto s = chain(arr1, arr2, arr3);
        assert(s[5] == 6);
        assert(equal(s, witness));
        assert(s[5] == 6);
    }
    {
        int[] arr1 = [ 1, 2, 3, 4 ];
        int[] witness = [ 1, 2, 3, 4 ];
        assert(equal(chain(arr1), witness));
    }
    {
        uint[] foo = [1,2,3,4,5];
        uint[] bar = [1,2,3,4,5];
        auto c = chain(foo, bar);
        c[3] = 42;
        assert(c[3] == 42);
    }

    // Make sure bug 3311 is fixed.  ChainImpl should compile even if not all
    // elements are mutable.
    auto c = chain( iota(0, 10), iota(0, 10) );

    // Check that chain at least instantiates and compiles with every possible
    // pair of DummyRange types, in either order.

    // This test should be uncommented when DMD bug 4379 gets fixed, or if
    // you've made sure you've turned off -O.  (Bug 4379 is triggered by -O).
//    foreach(DummyType1; AllDummyRanges) {
//        DummyType1 dummy1;
//        foreach(DummyType2; AllDummyRanges) {
//            DummyType2 dummy2;
//            auto myChain = chain(dummy1, dummy2);
//
//            static assert(
//                propagatesRangeType!(typeof(myChain), DummyType1, DummyType2)
//            );
//
//            assert(myChain.front == 1);
//            foreach(i; 0..dummyLength) {
//                myChain.popFront();
//            }
//            assert(myChain.front == 1);
//
//            static if(isBidirectionalRange!DummyType1 &&
//                      isBidirectionalRange!DummyType2) {
//                assert(myChain.back == 10);
//            }
//
//            static if(isRandomAccessRange!DummyType1 &&
//                      isRandomAccessRange!DummyType2) {
//                assert(myChain[0] == 1);
//            }
//        }
//    }
}

/**
Iterates a random-access range starting from a given point and
progressively extending left and right from that point. If no initial
point is given, iteration starts from the middle of the
range. Iteration spans the entire range.

Example:
----
int[] a = [ 1, 2, 3, 4, 5 ];
assert(equal(radial(a) == [ 3, 2, 4, 1, 5 ][]));
a = [ 1, 2, 3, 4 ];
assert(equal(radial(a) == [ 2, 3, 1, 4 ][]));
----
 */
struct Radial(R) if (isRandomAccessRange!(R) && hasLength!(R))
{
private:
    R _low, _up;
    bool _upIsActive;

public:
/**
Takes a range and starts iterating from its median point. Ranges with
an even length start iterating from the element to the left of the
median. The second iterated element, if any, is the one to the right
of the first iterated element. A convenient way to use this
constructor is by calling the helper function $(D radial(input)).
 */
    this(R input)
    {
        auto mid = (input.length + 1) / 2;
        _low = input[0 .. mid];
        _up = input[mid .. $];
    }

/**
Takes a range and starts iterating from $(D input[mid]). The second
iterated element, if any, is the one to the right of the first
iterated element. If there is no element to the right of $(D
input[mid]), iteration continues downwards with $(D input[mid - 1])
etc. A convenient way to use this constructor is by calling the helper
function $(D radial(input, startingPoint)).
 */
    this(R input, size_t startingPoint)
    {
        _low = input[0 .. startingPoint + 1];
        _up = input[startingPoint + 1 .. $];
        if (_low.empty) _upIsActive = true;
    }

/**
Returns $(D this).
 */
    ref Radial opSlice()
    {
        return this;
    }

/**
Range primitive operation that returns $(D true) iff there are no more
elements to be iterated.
 */
    @property bool empty()
    {
        return _low.empty && _up.empty;
    }

/**
Range primitive operation that advances the range to its next
element.
 */
    void popFront()
    {
        assert(!empty);
        // We started with low active
        if (!_upIsActive)
        {
            // Consumed the low part, now look in the upper part
            if (_up.empty)
            {
                // no more stuff up, attempt to continue in the low area
                _low.popBack;
            }
            else
            {
                // more stuff available in the upper area
                _upIsActive = true;
            }
        }
        else
        {
            // we consumed both the lower and the upper area, must
            // make real progress up there
            if (!_up.empty) _up.popFront;
            if (!_low.empty) _low.popBack;
            if (!_low.empty) _upIsActive = false;
        }
    }

/**
Range primitive operation that returns the currently iterated
element. Throws if the range is empty.
 */
    @property ref ElementType!(R) front()
    {
        enforce(!empty, "Calling front() against an empty "
                ~typeof(this).stringof);
        if (!_upIsActive)
        {
            // @@@ Damndest thing... removing the enforce below causes
            // a segfault in release unittest
            enforce(!_low.empty);
            return _low.back;
        }
        enforce(!_up.empty);
        return _up.front;
    }
}

/// Ditto
Radial!(R) radial(R)(R r)
    if (isRandomAccessRange!(R) && hasLength!(R))
{
    return Radial!(R)(r);
}

/// Ditto
Radial!(R) radial(R)(R r, size_t startingIndex)
    if (isRandomAccessRange!(R) && hasLength!(R))
{
    return Radial!(R)(r, startingIndex);
}

unittest
{
    void test(int[] input, int[] witness)
    {
        enforce(equal(radial(input), witness));
    }
    test([], []);
    test([ 1 ], [ 1 ]);
    test([ 1, 2 ], [ 1, 2 ]);
    test([ 1, 2, 3 ], [ 2, 3, 1 ]);
    test([ 1, 2, 3, 4 ], [ 2, 3, 1, 4 ]);
    test([ 1, 2, 3, 4, 5 ], [ 3, 4, 2, 5, 1 ]);
    test([ 1, 2, 3, 4, 5, 6 ], [ 3, 4, 2, 5, 1, 6 ]);
    int[] a = [ 1, 2, 3, 4, 5 ];
    assert(equal(radial(a, 1), [ 2, 3, 1, 4, 5 ][]));

    // Test instantiation without lvalue elements.

    // Doesn't instantiate!
    //DummyRange!(ReturnBy.Value, Length.Yes, RangeType.Random) dummy;
    //assert(equal(radial(dummy, 4), [5, 6, 4, 7, 3, 8, 2, 9, 1]));
}

/**
Lazily takes only up to $(D n) elements of a range. This is
particulary useful when using with infinite ranges. If the range
offers random access and $(D length), $(D Take) offers them as well.

Example:
----
int[] arr1 = [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
auto s = take(arr1, 5);
assert(s.length == 5);
assert(s[4] == 5);
assert(equal(s, [ 1, 2, 3, 4, 5 ][]));
----
 */
struct Take(R) if (isInputRange!(R))
{
    R original;
    private size_t _maxAvailable;
    enum bool byRef = is(typeof(&_input.front) == ElementType!(R)*);

public:
    alias R Source;

    static if (byRef)
        alias ref .ElementType!(R) ElementType;
    else
        alias .ElementType!(R) ElementType;

    @property bool empty()
    {
        return _maxAvailable == 0 || original.empty;
    }

    static if (isForwardRange!R)
        @property Take save()
        {
            return Take(original.save, _maxAvailable);
        }

    void popFront()
    {
        enforce(_maxAvailable > 0,
            "Attempting to popFront() past the end of a "
            ~ Take.stringof);
        original.popFront;
        --_maxAvailable;
    }

    @property ElementType front()
    {
        enforce(_maxAvailable > 0,
                "Attempting to fetch the front of an empty "
                ~ Take.stringof);
        return original.front;
    }

    static if (hasAssignableElements!R)
        @property void front(ElementType v)
        {
            original.front = v;
        }

    ElementType moveFront()
    {
        return .moveFront(original);
    }

    static if (isInfinite!(R))
    {
        @property size_t length() const
        {
            return _maxAvailable;
        }
    }
    else static if (hasLength!(R))
    {
        @property size_t length()
        {
            return min(_maxAvailable, original.length);
        }
    }

    static if (isRandomAccessRange!(R))
    {
        void popBack()
        {
            enforce(_maxAvailable > 0,
                "Attempting to popBack() past the beginning of a "
                ~ Take.stringof);
            --_maxAvailable;
        }

        mixin(
            (byRef ? "ref " : "")~
            q{/+auto ref+/ ElementType back()
            {
                return original[this.length - 1];
            }});

        mixin(
            (byRef ? "ref " : "")~
            q{/+auto ref+/ ElementType opIndex(size_t index)
            {
                enforce(index < this.length,
                    "Attempting to index out of the bounds of a "
                    ~ Take.stringof);
                return original[index];
            }});
    }

    Take opSlice() { return this; }

    @property size_t maxLength() const
    {
        return _maxAvailable;
    }
}

/// Ditto
Take!(R) take(R)(R input, size_t n) if (isInputRange!R && !hasSlicing!R)
{
    return Take!(R)(input, n);
}

/// Ditto
auto take(R)(R input, size_t n) if (isInputRange!R && hasSlicing!R)
{
    static if (hasLength!R)
    {
        // @@@BUG@@@
        //return input[0 .. min(n, @)];
        return input[0 .. min(n, input.length)];
    }
    else
    {
        static assert(isInfinite!R,
                "Nonsensical finite range with slicing but no length");
        return input[0 .. n];
    }
}

unittest
{
    int[] arr1 = [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ];
    auto s = take(arr1, 5);
    assert(s.length == 5);
    assert(s[4] == 5);
    assert(equal(s, [ 1, 2, 3, 4, 5 ][]));
    assert(equal(retro(s), [ 5, 4, 3, 2, 1 ][]));

    foreach(DummyType; AllDummyRanges) {
        DummyType dummy;
        auto t = take(dummy, 5);
        alias typeof(t) T;

        static if(isRandomAccessRange!DummyType) {
            static assert(isRandomAccessRange!T);
            assert(t[4] == 5);
        } else static if(isForwardRange!DummyType) {
            static assert(isForwardRange!T);
        }

        // Bidirectional ranges can't be propagated properly if they don't
        // also have random access.

        assert(equal(t, [1,2,3,4,5]));
    }
}

/**
Eagerly advances $(D r) itself (not a copy) $(D n) times (by calling
$(D r.popFront) $(D n) times). The pass of $(D r) into $(D popFrontN)
is by reference, so the original range is affected. Completes in
$(BIGOH 1) steps for ranges that support slicing, and in $(BIGOH n)
time for all other ranges.

Example:
----
int[] a = [ 1, 2, 3, 4, 5 ];
a.popFrontN(2);
assert(a == [ 3, 4, 5 ]);
----
 */
size_t popFrontN(Range)(ref Range r, size_t n) if (isInputRange!(Range))
{
    static if (hasSlicing!(Range) && hasLength!(Range))
    {
        n = min(n, r.length);
        r = r[n .. r.length];
    }
    else
    {
        foreach (i; 0 .. n)
        {
            if (r.empty) return i;
            r.popFront;
        }
    }
    return n;
}

unittest
{
    int[] a = [ 1, 2, 3, 4, 5 ];
    a.popFrontN(2);
    assert(a == [ 3, 4, 5 ]);
}

/**
Eagerly reduces $(D r) itself (not a copy) $(D n) times from its right
side (by calling $(D r.popBack) $(D n) times). The pass of $(D r) into
$(D popBackN) is by reference, so the original range is
affected. Completes in $(BIGOH 1) steps for ranges that support
slicing, and in $(BIGOH n) time for all other ranges.

Example:
----
int[] a = [ 1, 2, 3, 4, 5 ];
a.popBackN(2);
assert(a == [ 1, 2, 3 ]);
----
 */
size_t popBackN(Range)(ref Range r, size_t n) if (isInputRange!(Range))
{
    static if (hasSlicing!(Range) && hasLength!(Range))
    {
        auto newLen = n < r.length ? r.length - n : 0;
        n = r.length - newLen;
        r = r[0 .. newLen];
    }
    else
    {
        foreach (i; 0 .. n)
        {
            if (r.empty) return i;
            r.popBack;
        }
    }
    return n;
}

unittest
{
    int[] a = [ 1, 2, 3, 4, 5 ];
    a.popBackN(2);
    assert(a == [ 1, 2, 3 ]);
}

/**
Repeats one value forever. Example:
----
enforce(equal(take(repeat(5), 4), [ 5, 5, 5, 5 ][]));
----
 */

struct Repeat(T)
{
    private T _value;
    /// Range primitive implementations.
    @property ref T front() { return _value; }
    /// Ditto
    @property ref T back() { return _value; }
    /// Ditto
    enum bool empty = false;
    /// Ditto
    void popFront() {}
    /// Ditto
    void popBack() {}
    /// Ditto
    @property Repeat!(T) save() { return this; }
    /// Ditto
    ref T opIndex(uint) { return _value; }
}

/// Ditto
Repeat!(T) repeat(T)(T value) { return Repeat!(T)(value); }

unittest
{
    enforce(equal(take(repeat(5), 4), [ 5, 5, 5, 5 ][]));
    static assert(isForwardRange!(Repeat!(uint)));
}

/**
Replicates $(D value) exactly $(D n) times. Equivalent to $(D
take(repeat(value), n)).
 */
Take!(Repeat!(T)) replicate(T)(T value, size_t n)
{
    return take(repeat(value), n);
}

unittest
{
    enforce(equal(replicate(5, 4), [ 5, 5, 5, 5 ][]));
}

/**
Repeats the given forward range ad infinitum. If the original range is
infinite (fact that would make $(D Cycle) the identity application),
$(D Cycle) detects that and aliases itself to the range type
itself. If the original range has random access, $(D Cycle) offers
random access and also offers a constructor taking an initial position
$(D index). $(D Cycle) is specialized for statically-sized arrays,
mostly for performance reasons.

Example:
----
assert(equal(take(cycle([1, 2][]), 5), [ 1, 2, 1, 2, 1 ][]));
----

Tip: This is a great way to implement simple circular buffers.
 */
struct Cycle(R) if (isForwardRange!(R) && !isInfinite!(R))
{
    static if (isRandomAccessRange!(R) && hasLength!(R))
    {
        R _original;
        size_t _index;
        this(R input, size_t index = 0) { _original = input; _index = index; }
        /// Range primitive implementations.
        @property ref ElementType!(R) front()
        {
            return _original[_index % _original.length];
        }
        /// Ditto
        enum bool empty = false;
        /// Ditto
        void popFront() { ++_index; }
        ref ElementType!(R) opIndex(size_t n)
        {
            return _original[(n + _index) % _original.length];
        }
        /// Ditto
        @property Cycle!(R) save() {
            return Cycle!(R)(this._original.save, this._index);
        }
    }
    else
    {
        R _original, _current;
        this(R input) { _original = input; _current = input.save; }
        /// Range primitive implementations.
        @property ref ElementType!(R) front() { return _current.front; }
        /// Ditto
        static if (isBidirectionalRange!(R))
            @property ref ElementType!(R) back() { return _current.back; }
        /// Ditto
        enum bool empty = false;
        /// Ditto
        void popFront()
        {
            _current.popFront;
            if (_current.empty) _current = _original;
        }

        @property Cycle!(R) save() {
            Cycle!(R) ret;
            ret._original = this._original.save;
            ret._current =  this._current.save;
            return ret;
        }

    }
}

/// Ditto
template Cycle(R) if (isInfinite!(R))
{
    alias R Cycle;
}

/// Ditto
struct Cycle(R) if (isStaticArray!(R))
{
    private alias typeof(R[0]) ElementType;
    private ElementType* _ptr;
    private size_t _index;

    this(ref R input, size_t index = 0)
    {
        _ptr = input.ptr;
        _index = index;
    }
    /// Range primitive implementations.
    @property ref ElementType front()
    {
        return _ptr[_index % R.length];
    }
    /// Ditto
    enum bool empty = false;
    /// Ditto
    void popFront() { ++_index; }
    ref ElementType opIndex(size_t n)
    {
        return _ptr[(n + _index) % R.length];
    }

    @property Cycle!(R) save() {
        return this;
    }
}

/// Ditto
Cycle!(R) cycle(R)(R input) if (isForwardRange!(R) && !isInfinite!(R))
{
    return Cycle!(R)(input);
}

/// Ditto
Cycle!(R) cycle(R)(R input, size_t index) if (isRandomAccessRange!(R) && !isInfinite!(R))
{
    return Cycle!(R)(input, index);
}

/// Ditto
Cycle!(R) cycle(R)(R input) if (isInfinite!(R))
{
    return input;
}

/// Ditto
Cycle!(R) cycle(R)(ref R input, size_t index = 0) if (isStaticArray!R)
{
    return Cycle!(R)(input, index);
}

unittest
{
    assert(equal(take(cycle([1, 2][]), 5), [ 1, 2, 1, 2, 1 ][]));
    static assert(isForwardRange!(Cycle!(uint[])));

    int[3] a = [ 1, 2, 3 ];
    static assert(isStaticArray!(typeof(a)));
    auto c = cycle(a);
    assert(a.ptr == c._ptr);
    assert(equal(take(cycle(a), 5), [ 1, 2, 3, 1, 2 ][]));
    static assert(isForwardRange!(typeof(c)));

    foreach(DummyType; AllDummyRanges) {
        // Bug 4387
        static if(isForwardRange!(DummyType) && DummyType.r == ReturnBy.Reference) {
            DummyType dummy;
            auto cy = cycle(dummy);
            static assert(isForwardRange!(typeof(cy)));
            auto t = take(cy, 20);
            assert(equal(t, [1,2,3,4,5,6,7,8,9,10,1,2,3,4,5,6,7,8,9,10]));
        }
    }
}

unittest // For infinite ranges
{
    struct InfRange
    {
        void popFront() { }
        int front() { return 0; }
        enum empty = false;
    }

    InfRange i;
    auto c = cycle(i);
    assert (c == i);
}

/**
Iterate several ranges in lockstep. The element type is a proxy tuple
that allows accessing the current element in the $(D n)th range by
using $(D e.at!(n)).

Example:
----
int[] a = [ 1, 2, 3 ];
string[] b = [ "a", "b", "c" ];
// prints 1:a 2:b 3:c
foreach (e; zip(a, b))
{
    write(e.at!(0), ':', e.at!(1), ' ');
}
----

$(D Zip) offers the lowest range facilities of all components, e.g. it
offers random access iff all ranges offer random access, and also
offers mutation and swapping if all ranges offer it. Due to this, $(D
Zip) is extremely powerful because it allows manipulating several
ranges in lockstep. For example, the following code sorts two arrays
in parallel:

----
int[] a = [ 1, 2, 3 ];
string[] b = [ "a", "b", "c" ];
sort!("a.at!(0) > b.at!(0)")(zip(a, b));
assert(a == [ 3, 2, 1 ]);
assert(b == [ "c", "b", "a" ]);
----
 */
struct Zip(R...) if (R.length && allSatisfy!(isInputRange, R))
{
    Tuple!(R) ranges;
    StoppingPolicy stoppingPolicy = StoppingPolicy.shortest;

/**
Builds an object. Usually this is invoked indirectly by using the
$(XREF range,zip) function.
 */
    this(R rs, StoppingPolicy s = StoppingPolicy.shortest)
    {
        stoppingPolicy = s;
        foreach (i, Unused; R)
        {
            ranges.field[i] = rs[i];
        }
    }

/**
Returns $(D true) if the range is at end. The test depends on the
stopping policy.
 */
    bool empty()
    {
        bool firstRangeIsEmpty = ranges.field[0].empty;
        if (firstRangeIsEmpty && stoppingPolicy == StoppingPolicy.shortest)
            return true;
        foreach (i, Unused; R[1 .. $])
        {
            switch (stoppingPolicy)
            {
            case StoppingPolicy.shortest:
                if (ranges.field[i + 1].empty) return true;
                break;
            case StoppingPolicy.longest:
                if (!ranges.field[i + 1].empty) return false;
                break;
            default:
                assert(stoppingPolicy == StoppingPolicy.requireSameLength);
                enforce(firstRangeIsEmpty == ranges.field[i + 1].empty,
                        "Inequal-length ranges passed to Zip");
                break;
            }
        }
        return firstRangeIsEmpty;
    }

    static if (allSatisfy!(isForwardRange, R))
        @property Zip save()
        {
            Zip result;
            result.stoppingPolicy = stoppingPolicy;
            foreach (i, Unused; R)
            {
                result.ranges.field[i] = ranges.field[i].save;
            }
            return result;
        }

/**
Returns a proxy for the current iterated element.
 */
    @property Proxy front()
    {
        Proxy result;
        foreach (i, Unused; R)
        {
            result.ptrs.field[i] = &ranges.field[i].front;
        }
        return result;
    }

/**
Returns a proxy for the rightmost element.
 */
    @property Proxy back()
    {
        Proxy result;
        foreach (i, Unused; R)
        {
            result.ptrs.field[i] = &ranges.field[i].back;
        }
        return result;
    }

/**
Advances to the popFront element in all controlled ranges.
 */
    void popFront()
    {
        foreach (i, Unused; R)
        {
            ranges.field[i].popFront;
        }
    }

/**
Calls $(D popBack) for all controlled ranges.
 */
    void popBack()
    {
        foreach (i, Unused; R)
        {
            ranges.field[i].popBack;
        }
    }

/**
Returns the length of this range. Defined only if all ranges define
$(D length).
 */
    static if (allSatisfy!(hasLength, R))
        @property size_t length()
        {
            auto result = ranges.field[0].length;
            if (stoppingPolicy == StoppingPolicy.requireSameLength)
                return result;
            foreach (i, Unused; R[1 .. $])
            {
                if (stoppingPolicy == StoppingPolicy.shortest)
                {
                    result = min(ranges.field[i + 1].length, result);
                }
                else
                {
                    assert(stoppingPolicy == StoppingPolicy.longest);
                    result = max(ranges.field[i + 1].length, result);
                }
            }
            return result;
        }

/**
Returns a slice of the range. Defined only if all range define
slicing.
 */
    static if (allSatisfy!(hasSlicing, R))
        Zip!(R) opSlice(size_t from, size_t to)
        {
            Zip!(R) result;
            foreach (i, Unused; R)
            {
                result.ranges.field[i] = ranges.field[i][from .. to];
            }
            return result;
        }

/**
Proxy type returned by the access function.
*/
    struct Proxy
    {
        template ElemPtr(Range)
        {
            alias std.range.ElementType!(Range)* ElemPtr;
        }
        Tuple!(staticMap!(ElemPtr, R)) ptrs;

/**
Returns the current element in the $(D i)th range.
 */
        /*ref*/ std.range.ElementType!(R[i]) at(int i)()
        {
            return *ptrs.field[i];
        }

/**
Returns whether the current element exists in the $(D i)th range. This
function returns $(D false) if e.g. one of the ranges has exhausted in
the $(D StoppingPolicy.longest) policy.
 */
        bool hasAt(int i)()
        {
            return *ptrs.field[i];
        }

        void proxySwap(Proxy rhs)
        {
            foreach (i, Unused; R)
            {
                .swap(*ptrs.field[i], *rhs.ptrs.field[i]);
            }
        }
    }

/**
Returns the $(D n)th element in the composite range. Defined if all
ranges offer random access.
 */
    static if (allSatisfy!(isRandomAccessRange, R))
        Proxy opIndex(size_t n)
        {
            Proxy result;
            foreach (i, Unused; R)
            {
                result.ptrs.field[i] = &ranges.field[i][n];
            }
            return result;
        }
}

/// Ditto
Zip!(R) zip(R...)(R ranges)
    //if (allSatisfy!(isInputRange, R))
{
    return Zip!(R)(ranges);
}

/// Ditto
Zip!(R) zip(R...)(StoppingPolicy sp, R ranges)
    //if (allSatisfy!(isInputRange, R))
{
    return Zip!(R)(ranges, sp);
}

/**
Dictates how iteration in a $(D Zip) should stop. By default stop at
the end of the shortest of all ranges.
 */
enum StoppingPolicy
{
    /// Stop when the shortest range is exhausted
    shortest,
    /// Stop when the longest range is exhausted
    longest,
    /// Require that all ranges are equal
    requireSameLength,
}

unittest
{
    int[] a = [ 1, 2, 3 ];
    float[] b = [ 1., 2, 3 ];
    foreach (e; zip(a, b))
    {
        assert(e.at!(0) == e.at!(1));
    }
    auto z = zip(a, b);
    swap(z.front(), z.back());
    //@@@BUG@@@
    //sort!("a.at!(0) < b.at!(0)")(zip(a, b));

// Horribly broken.  See bugs 4402, 3123
//    foreach(DummyType1; AllDummyRanges) {
//        DummyType1 d1;
//        foreach(DummyType2; AllDummyRanges) {
//            DummyType2 d2;
//            auto r = zip(d1, d2);
//
//            assert(equal(map!"a.at!0"(r), [1,2,3,4,5,6,7,8,9,10]));
//            assert(equal(map!"a.at!1"(r), [1,2,3,4,5,6,7,8,9,10]));
//        }
//    }
}

/**
Creates a mathematical sequence given the initial values and a
recurrence function that computes the popFront value from the existing
values. The sequence comes in the form of an infinite forward
range. The type $(D Recurrence) itself is seldom used directly; most
often, recurrences are obtained by calling the function $(D
recurrence).

When calling $(D recurrence), the function that computes the next
value is specified as a template argument, and the initial values in
the recurrence are passed as regular arguments. For example, in a
Fibonacci sequence, there are two initial values (and therefore a
state size of 2) because computing the popFront Fibonacci value needs the
past two values.

If the function is passed in string form, the state has name $(D "a")
and the zero-based index in the recurrence has name $(D "n"). The
given string must return the desired value for $(D a[n]) given $(D a[n
- 1]), $(D a[n - 2]), $(D a[n - 3]),..., $(D a[n - stateSize]). The
state size is dictated by the number of arguments passed to the call
to $(D recurrence). The $(D Recurrence) class itself takes care of
managing the recurrence's state and shifting it appropriately.

Example:
----
// a[0] = 1, a[1] = 1, and compute a[n+1] = a[n-1] + a[n]
auto fib = recurrence!("a[n-1] + a[n-2]")(1, 1);
// print the first 10 Fibonacci numbers
foreach (e; take(fib, 10)) { writeln(e); }
// print the first 10 factorials
foreach (e; take(recurrence!("a[n-1] * n")(1), 10)) { writeln(e); }
----
 */
struct Recurrence(alias fun, StateType, size_t stateSize)
{
    StateType[stateSize] _state;
    size_t _n;

    this(StateType[stateSize] initial) { _state = initial; }

    void popFront()
    {
        _state[_n % stateSize] = binaryFun!(fun, "a", "n")(
            cycle(_state, _n), _n + stateSize);
        ++_n;
    }

    @property StateType front()
    {
        return _state[_n % stateSize];
    }

    enum bool empty = false;
}

/// Ditto
Recurrence!(fun, CommonType!(State), State.length)
recurrence(alias fun, State...)(State initial)
{
    CommonType!(State)[State.length] state;
    foreach (i, Unused; State)
    {
        state[i] = initial[i];
    }
    return typeof(return)(state);
}

version(none) unittest
{
    auto fib = recurrence!("a[n-1] + a[n-2]")(1, 1);
    int[] witness = [1, 1, 2, 3, 5, 8, 13, 21, 34, 55 ];
    //foreach (e; take(fib, 10)) writeln(e);
    assert(equal(take(fib, 10), witness));
    foreach (e; take(fib, 10)) {}//writeln(e);
    //writeln(s.front);
    auto fact = recurrence!("n * a[n-1]")(1);
    assert( equal(take(fact, 10), [1, 1, 2, 2*3, 2*3*4, 2*3*4*5, 2*3*4*5*6,
                            2*3*4*5*6*7, 2*3*4*5*6*7*8, 2*3*4*5*6*7*8*9][]) );
    auto piapprox = recurrence!("a[n] + (n & 1 ? 4. : -4.) / (2 * n + 3)")(4.);
    foreach (e; take(piapprox, 20)) {}//writeln(e);
}

/**
$(D Sequence) is similar to $(D Recurrence) except that iteration is
presented in the so-called $(WEB en.wikipedia.org/wiki/Closed_form,
closed form). This means that the $(D n)th element in the series is
computable directly from the initial values and $(D n) itself. This
implies that the interface offered by $(D Sequence) is a random-access
range, as opposed to the regular $(D Recurrence), which only offers
forward iteration.

The state of the sequence is stored as a $(D Tuple) so it can be
heterogeneous.

Example:
----
// a[0] = 1, a[1] = 2, a[n] = a[0] + n * a[1]
auto odds = sequence!("a[0] + n * a[1]")(1, 2);
----
 */
struct Sequence(alias fun, State)
{
private:
    alias binaryFun!(fun, "a", "n") compute;
    alias typeof(compute(State.init, 1u)) ElementType;
    State _state;
    size_t _n;
    ElementType _cache;

public:
    this(State initial, size_t n = 0)
    {
        this._state = initial;
        this._n = n;
        this._cache = compute(this._state, this._n);
    }

    @property ElementType front()
    {
        //return ElementType.init;
        return this._cache;
    }

    ElementType moveFront()
    {
        return move(_cache);
    }

    void popFront()
    {
        this._cache = compute(this._state, ++this._n);
    }

    ElementType opIndex(size_t n)
    {
        //return ElementType.init;
        return compute(this._state, n + this._n);
    }

    enum bool empty = false;

    @property Sequence save() { return this; }
}

/// Ditto
Sequence!(fun, Tuple!(State)) sequence
    (alias fun, State...)(State args)
{
    return typeof(return)(tuple(args));
}

unittest
{
    // alias Sequence!("a.field[0] += a.field[1]",
    //         Tuple!(int, int)) Gen;
    // Gen x = Gen(tuple(0, 5));
    // foreach (e; take(x, 15))
    // {}//writeln(e);

    auto y = Sequence!("a.field[0] + n * a.field[1]", Tuple!(int, int))
        (tuple(0, 4));
    //@@BUG
    //auto y = sequence!("a.field[0] + n * a.field[1]")(0, 4);
    //foreach (e; take(y, 15))
    {}//writeln(e);

    auto odds = Sequence!("a.field[0] + n * a.field[1]", Tuple!(int, int))(tuple(1, 2));
    for(int currentOdd = 1; currentOdd <= 21; currentOdd += 2) {
        assert(odds.front == odds[0]);
        assert(odds[0] == currentOdd);
        odds.popFront();
    }
}

/**
Returns a range that goes through the numbers $(D begin), $(D begin +
step), $(D begin + 2 * step), $(D ...), up to and excluding $(D
end). The range offered is a random access range. The two-arguments
version has $(D step = 1).

Example:
----
auto r = iota(0, 10, 1);
assert(equal(r, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9][]));
r = iota(0, 11, 3);
assert(equal(r, [0, 3, 6, 9][]));
assert(r[2] == 6);
auto rf = iota(0.0, 0.5, 0.1);
assert(equal(rf, [0.0, 0.1, 0.2, 0.3, 0.4]));
----
 */
Iota!(CommonType!(B, E), S) iota(B, E, S)(B begin, E end, S step)
if (is(typeof((E.init - B.init) + 1 * S.init)))
{
    return Iota!(CommonType!(B, E), S)(begin, end, step);
}

/// Ditto
Iota!(CommonType!(B, E), uint) iota(B, E)(B begin, E end)
{
    return iota(begin, end, 1u);
}

/// Ditto
Iota!(E, uint) iota(E)(E end)
{
    E begin = 0;
    return iota(begin, end, 1u);
}

// Iota for integers and pointers
/// Ditto
struct Iota(N, S) if ((isIntegral!N || isPointer!N) && isIntegral!S) {
    private N current, pastLast;
    private S step;
    this(N current, N pastLast, S step)
    {
        enforce(step != 0 && current != pastLast);
        this.current = current;
        this.step = step;
        if (step > 0)
        {
            this.pastLast = pastLast - 1;
            this.pastLast -= (this.pastLast - current) % step;
        }
        else
        {
            this.pastLast = pastLast + 1;
            this.pastLast += (this.pastLast - current) % step;
        }
        this.pastLast += step;
    }
    /// Ditto
    @property bool empty() const { return current == pastLast; }
    /// Ditto
    @property N front() { return current; }
    /// Ditto
    alias front moveFront;
    /// Ditto
    void popFront()
    {
        current += step;
    }
    /// Ditto
    @property N back() { return pastLast - step; }
    /// Ditto
    alias back moveBack;
    /// Ditto
    void popBack()
    {
        pastLast -= step;
    }
    /// Ditto
    @property Iota save() { return this; }
    /// Ditto
    N opIndex(size_t n)
    {
        return current + step * n;
    }
    /// Ditto
    @property Select!(max(N.sizeof, S.sizeof) > size_t.sizeof, ulong, size_t)
    length() const
    {
        return (pastLast - current) / step;
    }
}

// Iota for floating-point numbers
/// Ditto
struct Iota(N, S) if (isFloatingPoint!N && isNumeric!S) {
    private N start;
    private S step;
    private size_t index, count;
    this(N start, N end, S step)
    {
        this.start = start;
        this.step = step;
        enforce(step != 0);
        immutable fcount = (end - start) / step;
        enforce(fcount >= 0, "iota: incorrect startup parameters");
        count = to!size_t(fcount);
        auto pastEnd = start + count * step;
        if (step > 0)
        {
            if (pastEnd < end) ++count;
            assert(start + count * step >= end);
        }
        else
        {
            if (pastEnd > end) ++count;
            assert(start + count * step <= end);
        }
    }
    /// Range primitives
    @property bool empty() const { return index == count; }
    /// Ditto
    @property N front() { return start + step * index; }
    /// Ditto
    alias front moveFront;
    /// Ditto
    void popFront()
    {
        enforce(!empty);
        ++index;
    }
    /// Ditto
    @property N back()
    {
        enforce(!empty);
        return start + step * (count - 1);
    }
    /// Ditto
    alias back moveBack;
    /// Ditto
    void popBack()
    {
        enforce(!empty);
        --count;
    }
    /// Ditto
    @property Iota save() { return this; }
    /// Ditto
    N opIndex(size_t n)
    {
        enforce(n < count);
        return start + step * n;
    }
    /// Ditto
    @property size_t length() const
    {
        return count;
    }
}

unittest
{
    auto r = iota(0, 10, 1);
    assert(equal(r, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9][]));
    auto rr = iota(10);
    assert(equal(rr, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9][]));
    r = iota(0, -10, -1);
    assert(equal(r, [0, -1, -2, -3, -4, -5, -6, -7, -8, -9][]));
    r = iota(0, 11, 3);
    assert(equal(r, [0, 3, 6, 9][]));
    assert(r[2] == 6);

    int[] a = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
    auto r1 = iota(a.ptr, a.ptr + a.length, 1);
    assert(r1.front == a.ptr);
    assert(r1.back == a.ptr + a.length - 1);
    auto rf = iota(0.0, 0.5, 0.1);
    //foreach (e; rf) writeln(e);
    assert(approxEqual(rf, [0.0, 0.1, 0.2, 0.3, 0.4][]));
    // With something just above 0.5
    rf = iota(0.0, nextUp(0.5), 0.1);
    //foreach (e; rf) writeln(e);
    assert(approxEqual(rf, [0.0, 0.1, 0.2, 0.3, 0.4, 0.5][]));

    // going down
    rf = iota(0.0, -0.5, -0.1);
    //foreach (e; rf) writeln(e);
    assert(approxEqual(rf, [0.0, -0.1, -0.2, -0.3, -0.4][]));
    rf = iota(0.0, nextDown(-0.5), -0.1);
    //foreach (e; rf) writeln(e);
    assert(approxEqual(rf, [0.0, -0.1, -0.2, -0.3, -0.4, -0.5][]));

    // iota of longs
    auto rl = iota(5_000_000L);
    assert(rl.length == 5_000_000L);
}

unittest
{
    auto idx = new size_t[100];
    copy(iota(0, idx.length), idx);
}

/**
Options for the $(D FrontTransversal) and $(D Transversal) ranges
(below).
 */
enum TransverseOptions
{
/**
When transversed, the elements of a range of ranges are assumed to
have different lengths (e.g. a jagged array).
 */
    assumeJagged, //default
/**
The transversal enforces that the elements of a range of ranges have
all the same length (e.g. an array of arrays, all having the same
length). Checking is done once upon construction of the transversal
range.
 */
    enforceNotJagged,
/**
The transversal assumes, without verifying, that the elements of a
range of ranges have all the same length. This option is useful if
checking was already done from the outside of the range.
 */
    assumeNotJagged,
}

/**
Given a range of ranges, iterate transversally through the first
elements of each of the enclosed ranges.

Example:
----
int[][] x = new int[][2];
x[0] = [1, 2];
x[1] = [3, 4];
auto ror = frontTransversal(x);
assert(equals(ror, [ 1, 3 ][]));
---
 */
struct FrontTransversal(RangeOfRanges,
        TransverseOptions opt = TransverseOptions.assumeJagged)
{
    alias typeof(RangeOfRanges.init.front().front()) ElementType;

    private void prime()
    {
        static if (opt == TransverseOptions.assumeJagged)
        {
            while (!_input.empty && _input.front.empty)
            {
                _input.popFront;
            }
            static if (isBidirectionalRange!RangeOfRanges)
            {
                while (!_input.empty && _input.back.empty)
                {
                    _input.popBack;
                }
            }
        }
    }

/**
   Construction from an input.
*/
    this(RangeOfRanges input)
    {
        _input = input;
        prime;
        static if (opt == TransverseOptions.enforceNotJagged)
            // (isRandomAccessRange!RangeOfRanges
            //     && hasLength!(.ElementType!RangeOfRanges))
        {
            if (empty) return;
            immutable commonLength = _input.front.length;
            foreach (e; _input)
            {
                enforce(e.length == commonLength);
            }
        }
    }

/**
   Forward range primitives.
*/
    @property bool empty()
    {
        return _input.empty;
    }

/// Ditto
    @property ref ElementType front()
    {
        assert(!empty);
        return _input.front.front;
    }

/// Ditto
    void popFront()
    {
        assert(!empty);
        _input.popFront;
        prime;
    }

    static if (isBidirectionalRange!RangeOfRanges)
    {
/**
   Bidirectional primitives. They are offered if $(D
isBidirectionalRange!RangeOfRanges).
 */
        @property ref ElementType back()
        {
            return _input.back.front;
        }
/// Ditto
        void popBack()
        {
            assert(!empty);
            _input.popBack;
            prime;
        }
    }

    static if (isRandomAccessRange!RangeOfRanges &&
            (opt == TransverseOptions.assumeNotJagged ||
                    opt == TransverseOptions.enforceNotJagged))
    {
/**
Random-access primitive. It is offered if $(D
isRandomAccessRange!RangeOfRanges && (opt ==
TransverseOptions.assumeNotJagged || opt ==
TransverseOptions.enforceNotJagged)).
 */
        ref ElementType opIndex(size_t n)
        {
            return _input[n].front;
        }
    }

    auto opSlice() { return this; }

private:
    RangeOfRanges _input;
}

/// Ditto
FrontTransversal!(RangeOfRanges, opt) frontTransversal(
    TransverseOptions opt = TransverseOptions.assumeJagged,
    RangeOfRanges)
(RangeOfRanges rr)
{
    return typeof(return)(rr);
}

unittest {
    foreach(DummyType; AllDummyRanges) {
        static if(DummyType.r == ReturnBy.Reference) { // Bug 4403
            auto dummies = [DummyType.init, DummyType.init];
            auto ft = frontTransversal(dummies);
            assert(equal(ft, [1, 1]));
        }
    }
}

/**
Given a range of ranges, iterate transversally through the the $(D
n)th element of each of the enclosed ranges. All elements of the
enclosing range must offer random access.

Example:
----
int[][] x = new int[][2];
x[0] = [1, 2];
x[1] = [3, 4];
auto ror = transversal(x, 1);
assert(equals(ror, [ 2, 4 ][]));
---
 */
struct Transversal(RangeOfRanges,
        TransverseOptions opt = TransverseOptions.assumeJagged)
{
    alias typeof(RangeOfRanges.init.front().front()) ElementType;

    private void prime()
    {
        static if (opt == TransverseOptions.assumeJagged)
        {
            while (!_input.empty && _input.front.length <= _n)
            {
                _input.popFront;
            }
            static if (isBidirectionalRange!RangeOfRanges)
            {
                while (!_input.empty && _input.back.length <= _n)
                {
                    _input.popBack;
                }
            }
        }
    }

/**
   Construction from an input and an index.
 */
    this(RangeOfRanges input, size_t n)
    {
        _input = input;
        _n = n;
        prime;
        static if (opt == TransverseOptions.enforceNotJagged)
        {
            if (empty) return;
            immutable commonLength = _input.front.length;
            foreach (e; _input)
            {
                enforce(e.length == commonLength);
            }
        }
    }

/**
   Forward range primitives.
*/
    @property bool empty()
    {
        return _input.empty;
    }

/// Ditto
    @property ref ElementType front()
    {
        assert(!empty);
        return _input.front[_n];
    }

/// Ditto
    void popFront()
    {
        assert(!empty);
        _input.popFront;
        prime;
    }

    static if (isBidirectionalRange!RangeOfRanges)
    {
/**
   Bidirectional primitives. They are offered if $(D
isBidirectionalRange!RangeOfRanges).
 */
        @property ref ElementType back()
        {
            return _input.back[_n];
        }
        void popBack()
        {
            assert(!empty);
            _input.popBack;
            prime;
        }
    }

    static if (isRandomAccessRange!RangeOfRanges &&
            (opt == TransverseOptions.assumeNotJagged ||
                    opt == TransverseOptions.enforceNotJagged))
    {
/**
Random-access primitive. It is offered if $(D
isRandomAccessRange!RangeOfRanges && (opt ==
TransverseOptions.assumeNotJagged || opt ==
TransverseOptions.enforceNotJagged)).
 */
        ref ElementType opIndex(size_t n)
        {
            return _input[n][_n];
        }
    }

    auto opSlice() { return this; }

private:
    RangeOfRanges _input;
    size_t _n;
}

/// Ditto
Transversal!(RangeOfRanges, opt) transversal
(TransverseOptions opt = TransverseOptions.assumeJagged, RangeOfRanges)
(RangeOfRanges rr, size_t n)
{
    return typeof(return)(rr, n);
}

unittest
{
    int[][] x = new int[][2];
    x[0] = [ 1, 2 ];
    x[1] = [3, 4];
    auto ror = transversal(x, 1);
    auto witness = [ 2, 4 ];
    uint i;
    foreach (e; ror) assert(e == witness[i++]);
    assert(i == 2);

    // Test w/o ref return.  Doesn't work due to bug 4404.
//    alias DummyRange!(ReturnBy.Value, Length.Yes, RangeType.Random) D;
//    auto drs = [D.init, D.init];
//    foreach(num; 0..10) {
//        auto t = transversal(drs, num);
//        assert(equal(t, [num + 1, num + 1]));
//  }
}

struct Transposed(RangeOfRanges)
{
    alias typeof(map!"a.front"(RangeOfRanges.init)) ElementType;

    this(RangeOfRanges input)
    {
        this._input = input;
    }

    @property ElementType front()
    {
        return map!"a.front"(_input);
    }

    void popFront()
    {
        foreach (ref e; _input)
        {
            if (e.empty) continue;
            e.popFront;
        }
    }

    // ElementType opIndex(size_t n)
    // {
    //     return _input[n].front;
    // }

    @property bool empty()
    {
        foreach (e; _input)
            if (!e.empty) return false;
        return true;
    }

    @property Transposed save()
    {
        return Transposed(_input.save);
    }

    auto opSlice() { return this; }

private:
    RangeOfRanges _input;
}

auto transposed(RangeOfRanges)(RangeOfRanges rr)
{
    return Transposed!RangeOfRanges(rr);
}

unittest
{
    int[][] x = new int[][2];
    x[0] = [1, 2];
    x[1] = [3, 4];
    auto tr = transposed(x);
    int[][] witness = [ [ 1, 3 ], [ 2, 4 ] ];
    uint i;

    foreach (e; tr)
    {
        assert(array(e) == witness[i++]);
    }
}

// Tests to see whether a struct has a postblit.  Hacky, probably needs to
// be fixed if a new frontend is ever written.
private template hasPostblit(R) {
    static if(!is(R == struct)) {
        enum bool hasPostblit = false;
    } else {
        enum hasPostblit = is(typeof({
            R r;
            return &r.__postblit;
        }));
    }
}

unittest {
    struct S {
        this(this) {}
    }

    struct S2 {}

    static assert(hasPostblit!S);
    static assert(!hasPostblit!S2);
}

/**
Moves the front of $(D r) out and returns it. Leaves $(D r.front) in a
destroyable state that does not allocate any resources (usually equal
to its $(D .init) value).
 */
ElementType!R moveFront(R)(R r)
{
    static if(is(typeof(&R.moveFront))) {
        return r.moveFront();
    } else static if(!hasPostblit!(ElementType!(R))) {
        return r.front;
    } else static if(is(typeof(&r.front()) == ElementType!R*)) {
        return move(r.front);
    } else {
        static assert(0,
            "Cannot move front of a range with a postblit and an rvalue front.");
    }
}

unittest
{
    struct R
    {
        ref int front() { static int x = 42; return x; }
        this(this){}
    }
    R r;
    assert(moveFront(r) == 42);
}

/**
Moves the front of $(D r) out and returns it. Leaves $(D r.front) in a
destroyable state that does not allocate any resources (usually equal
to its $(D .init) value).
 */
ElementType!R moveBack(R)(R r)
if (isInputRange!R && is(typeof(&r.front) == ElementType!R*))
{
    return move(r.back);
}

/// Ditto
ElementType!R moveBack(R)(R r)
if (isInputRange!R && is(typeof(&R.moveBack)))
{
    return r.moveBack();
}

/**
Moves element at index $(D i) of $(D r) out and returns it. Leaves $(D
r.front) in a destroyable state that does not allocate any resources
(usually equal to its $(D .init) value).
 */
ElementType!R moveAt(R)(R r, size_t i)
if (is(typeof(&r[i]) == ElementType!R*))
{
    return move(r[i]);
}

/// Ditto
ElementType!R moveAt(R)(R r, size_t i)
if (is(typeof(&R.moveAt)))
{
    return r.moveAt(i);
}

unittest
{
    auto a = [ 1, 2, 3 ];
    assert(moveFront(a) == 1);
    // define a perfunctory input range
    struct InputRange
    {
        @property bool empty() { return false; }
        @property int front() { return 42; }
        void popFront() {}
        int moveFront() { return 43; }
    }
    InputRange r;
    assert(moveFront(r) == 43);
}


//----------------------------------------------------------------------------//
// [devel] temporary
//----------------------------------------------------------------------------//

import core.stdc.stdlib : alloca;

@system
E* getNext(E, R)(ref R input, ref E store = *(cast(E*) alloca(E.sizeof)))
{
    static if (is(typeof(input.getNext(store)) == E*)
            /+ @@@ +/ && !isArray!(R))
    {
        return input.getNext(store);
    }
    else
    {
        if (input.empty)
            return null;

        static if (is(typeof(&(0, input.front)) == E*))
        {
            auto p = &(0, input.front);
            input.popFront;
            return p;
        }
        else
        {
            store = input.front;
            input.popFront;
            return &store;
        }
    }
}

