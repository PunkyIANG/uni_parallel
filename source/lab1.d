struct Range
{
    size_t[2] arrayof;
    alias arrayof this;

    size_t length() const { return arrayof[1] - arrayof[0] + 1; }
    bool contains(size_t a) const { return a >= arrayof[0] && a <= arrayof[1]; }
    bool contains(Range a) const { return a[0] >= arrayof[0] && a[1] <= arrayof[1]; }
    
    Range opBinary(string op, R)(const auto ref R rhs) const
    {
        mixin(`return Range([arrayof[0] `~op~` rhs[0], arrayof[1] `~op~` rhs[1]]);`);
    }
}

import std.algorithm.mutation : swap;

struct Matrix(T, bool Transposed = false)
{
    T* array;

    /// The actual width of the underlying matrix.
    size_t _width;
    /// The actual height of the underlying matrix.
    size_t _height;
    /// The width of the source matrix, as seen after transposition.
    size_t allWidth()  const { return Transposed ? _height : _width;  }
    /// The height of the source matrix, as seen after transposition.
    size_t allHeight() const { return Transposed ? _width  : _height; }

    Range _rowRange;
    Range _colRange;

    /// The width of the matrix, as available to the user.
    /// The user may provide as the second index the values in range [0, width).
    size_t width()  const { return Transposed ? _rowRange.length : _colRange.length; }
    /// The height of the matrix, as available to the user.
    /// The user may provide as the first index the values in range [0, height).
    size_t height() const { return Transposed ? _colRange.length : _rowRange.length; }

    inout(Matrix!(T, !Transposed)) transposed() inout
    {
        return typeof(return)(array, _width, _height, _rowRange, _colRange);
    }

    /// Returns the internal index into the underlying array.
    private size_t getLinearIndex(size_t rowIndex, size_t colIndex) const
    {
        assert(rowIndex >= 0 && rowIndex < _rowRange.length); 
        assert(colIndex >= 0 && colIndex < _colRange.length); 
        rowIndex = rowIndex + _rowRange[0]; 
        colIndex = colIndex + _colRange[0];
        return rowIndex * _width + colIndex;
    }

    auto ref inout(T) opIndex(size_t rowIndex, size_t colIndex) inout
    {
        if (Transposed)
            swap(rowIndex, colIndex);
        return array[getLinearIndex(rowIndex, colIndex)];
    }

    size_t opDollar(size_t dim : 0)() const { return height; }
    size_t opDollar(size_t dim : 1)() const { return width;  }
    // m[a..b, c] = m[a..b, c .. c + 1]
    auto inout opIndex(size_t[2] rows, size_t colIndex) { return opIndex(rows, [colIndex, colIndex + 1]); }
    // m[a, b..c] = m[a .. a + 1, b..c]
    auto inout opIndex(size_t rowIndex, size_t[2] cols) { return opIndex([rowIndex, rowIndex + 1], cols); }

    inout(Matrix!(T, Transposed)) opIndex(size_t[2] row, size_t[2] col) inout
    {
        if (Transposed)
            swap(row, col);
            
        Range newRowRange = Range([_rowRange[0] + row[0], _rowRange[0] + row[1] - 1]);
        assert(_rowRange.contains(newRowRange));

        Range newColRange = Range([_colRange[0] + col[0], _colRange[0] + col[1] - 1]);
        assert(_colRange.contains(newColRange));

        return typeof(return)(array, _width, _height, newRowRange, newColRange);        
    }

    // Support for `x..y` notation in slicing operator for the given dimension.
    size_t[2] opSlice(size_t dim)(size_t start, size_t end) const if (dim >= 0 && dim < 2)
    {
        return [start, end];
    }
}

Matrix!T matrixFromArray(T)(T[] array, size_t width)
{
    auto height = array.length / width;
    return Matrix!T(array.ptr, width, height, Range([0, height]), Range([0, width]));
}

unittest
{
    auto matrix = matrixFromArray([ 1, 2, 3,
                                    4, 5, 6,
                                    7, 8, 9, ], 3);
    assert(matrix[0, 0] == 1);
    assert(matrix[0, 1] == 2);
    assert(matrix[0, 2] == 3);
    assert(matrix[1, 0] == 4);
    assert(matrix[1, 1] == 5);
    assert(matrix[1, 2] == 6);

    auto matrixT = matrix.transposed;
    pragma(msg, typeof(matrixT));

    assert(matrixT[0, 0] == 1);
    assert(matrixT[0, 1] == 4);
    assert(matrixT[0, 2] == 7);
    assert(matrixT[1, 0] == 2);
    assert(matrixT[1, 1] == 5);
    assert(matrixT[1, 2] == 8);

    matrix = matrix[1..$, 1..$];

    assert(matrix[0, 0] == 5);
    assert(matrix[0, 1] == 6);
    assert(matrix[1, 0] == 8);
    assert(matrix[1, 1] == 9);

    matrixT = matrix.transposed;

    assert(matrixT[0, 0] == 5);
    assert(matrixT[0, 1] == 8);
    assert(matrixT[1, 0] == 6);
    assert(matrixT[1, 1] == 9);

    matrix = matrixFromArray([ 1, 2, 3, 3, 2, 1,
                               4, 5, 6, 6, 5, 4,
                               7, 8, 9, 9, 8, 7, ], 6);

    matrixT = matrix.transposed;

    assert(matrix[0, 3] == 3);
    assert(matrix[2, 5] == 7);

    // [   1, 4, 7,
    //     2, 5, 8, 
    //     3, 6, 9, 
    //     3, 6, 9, 
    //     2, 5, 8, 
    //     1, 4, 7, ];
    assert(matrixT[0, 2] == 7);
    assert(matrixT[3, 0] == 3);
    assert(matrixT[4, 0] == 2);
    assert(matrixT[4, 2] == 8);

    matrix = matrix[1..$, 3..$];

    assert(matrix[0, 0] == 6);
    assert(matrix[0, 1] == 5);

    matrixT = matrix.transposed;

    // [   6, 9, 
    //     5, 8, 
    //     4, 7, ];
    assert(matrixT[0, 0] == 6);
    assert(matrixT[1, 1] == 8);
    assert(matrixT[2, 1] == 7);

    // take first row, all columns
    auto firstRow = matrix[0, 0..$];
    foreach (i; 0..matrix.width)
        assert(firstRow[0, i] == matrix[0, i]); 

    auto firstRowAsColumn = firstRow.transposed;
    foreach (i; 0..matrix.height)
        assert(firstRowAsColumn[i, 0] == matrix[0, i]); 

    auto firstTwo = firstRowAsColumn[2..4, 0];
    assert(firstTwo.width == 1);
    assert(firstTwo.height == 2);
    foreach (i; 0..2)
        assert(firstTwo[i, 0] == matrix[0, i + 2]);
}
unittest
{
    const(Matrix!int) constMatrix;
    static assert(is(typeof(constMatrix[0..1, 0..2]) == const(Matrix!int)));
    immutable(Matrix!int) immutableMatrix;
    static assert(is(typeof(immutableMatrix[0..0, 0]) == typeof(immutableMatrix)));
    static assert(is(typeof(immutableMatrix.array) == immutable(int*)));
    static assert(is(typeof(immutableMatrix[0, 0]) == immutable(int)));
    static assert(is(typeof(immutableMatrix.transposed()) == immutable(Matrix!(int, true))));
    static assert(!__traits(compiles, constMatrix[0, 0] = 2));
    static assert(!__traits(compiles, immutableMatrix[0, 0] = 2));
}