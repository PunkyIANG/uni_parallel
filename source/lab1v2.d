module lab1v2;

import mpi;
import core.runtime : Runtime, CArgs;
import std.stdio : writeln, writefln;

const int intBitLength = int.sizeof * 8;

// A - coloane
// B - linii

// 0     :0
// 1 ..32:1
// 33..64:2
// basically (bitLen + 31)/32
int GetBitmapLength(int rowLength)
{
    int actualLength = rowLength ^^ 2;

    return (actualLength + intBitLength - 1) / intBitLength;
}

void SetRow(int[] bitmap, int rowLength, int rowId)
{
    assert(bitmap.length * intBitLength >= rowLength ^^ 2);
    assert(rowId < rowLength);

    int startPos = rowId * rowLength;
    int endPos = (rowId + 1) * rowLength; //exclusive

    foreach (index; startPos .. endPos)
    {
        int intIndex = index / intBitLength;
        int bitIndex = index % intBitLength;

        bitmap[intIndex] |= 1 << bitIndex;
    }
}

void Print(int[] bitmap)
{
    foreach (elem; bitmap)
    {
        writefln("%032b", elem);
    }
    writeln();
}

void SetCol(int[] dest, int[] source, int rowLength, int colId)
{
    int startPos = colId;
    int endPos = rowLength * (rowLength - 1) + colId;

    for (int index = startPos; index <= endPos; index += rowLength)
    {
        int intIndex = index / intBitLength;
        int bitIndex = index % intBitLength;

        int currBit = 1 << bitIndex;

        // basically set dest's current bit to be equal to source's bit
        // first set it to 0, then || it to whatever source is

        dest[intIndex] = (~currBit & dest[intIndex]) | (currBit & source[intIndex]);

    }
}

void SumCol(int[] dest, int[] source, int rowLength, int colId)
{
    int startPos = colId;
    int endPos = rowLength * (rowLength - 1) + colId;

    for (int index = startPos; index <= endPos; index += rowLength)
    {
        int intIndex = index / intBitLength;
        int bitIndex = index % intBitLength;

        int currBit = 1 << bitIndex;

        dest[intIndex] |= currBit & source[intIndex];
    }
}

int[] CreateDataRow(int[] matrixRow, int rowId)
{
    assert(matrixRow.length > rowId);
    int rowLength = cast(int) matrixRow.length;
    int[] result = rowLength ~ matrixRow ~ new int[GetBitmapLength(rowLength)];

    result[rowLength + 1 .. $].SetRow(rowLength, rowId);

    return result;
}

void Compare(int[] destination, int[] source)
{
    assert(source.length == destination.length);
    assert(source[0] == destination[0]);

    int rowLength = source[0];

    int[] matrixRowA = source[1 .. rowLength + 1];
    int[] matrixRowB = destination[1 .. rowLength + 1];

    int[] bitmaskA = source[rowLength + 1 .. $];
    int[] bitmaskB = destination[rowLength + 1 .. $];

    foreach (index; 0 .. rowLength)
    {
        if (matrixRowA[index] == matrixRowB[index])
        {
            bitmaskB.SumCol(bitmaskA, rowLength, index);
        }
        else if (matrixRowA[index] > matrixRowB[index])
        {
            bitmaskB.SetCol(bitmaskA, rowLength, index);
            matrixRowB[index] = matrixRowA[index];
        }
        // if b < a then do nothing
    }
}

extern (C) void SearchMax(void* a, void* b, int* len, MPI_Datatype* dt)
{
    int length = *len;

    int[] input = (cast(int*) a)[0 .. length];
    int[] output = (cast(int*) b)[0 .. length];

    output.Compare(input);

    writeln(output);
}

int main()
{
    const int root = 0;
    int size, rank;

    int rowLength = 3;
    int[] A, B;
    int[] Acol = new int[rowLength], Brow = new int[rowLength];

    auto args = Runtime.cArgs;
    MPI_Init(&args.argc, &args.argv);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);

    MPI_Op operation;
    MPI_Op_create(&SearchMax, 1, &operation);

    if (rank == root)
    {
        A = [1, 2, 3, 4, 5, 6, 7, 8, 9];

        B = [10, 11, 12, 13, 14, 15, 16, 17, 18];
    }

    int[] Invert(int[] matrix)
    {
        writeln(matrix.length);
        writeln(rowLength);
        int[] result = new int[matrix.length];

        foreach (rowId; 0 .. rowLength)
            foreach (colId; 0 .. rowLength)
            {
                writefln("%d %d", rowId, colId);
                result[rowId * rowLength + colId] = matrix[colId * rowLength + rowId];
            }

        return result;
    }

    // MPI_Scatter(Invert(A).ptr, rowLength, MPI_INT, Acol.ptr, rowLength,
    //         MPI_INT, root, MPI_COMM_WORLD);

    MPI_Scatter(A.ptr, rowLength, MPI_INT, Acol.ptr, rowLength, MPI_INT, root, MPI_COMM_WORLD);
    MPI_Scatter(B.ptr, rowLength, MPI_INT, Brow.ptr, rowLength, MPI_INT, root, MPI_COMM_WORLD);

    int[] Adata = Acol.CreateDataRow(rank);
    int[] Bdata = Brow.CreateDataRow(rank);

    writeln("Adata:");
    writeln(Adata);
    Bdata[rowLength + 1 .. $].Print();

    writeln("Bdata:");
    writeln(Bdata);
    Bdata[rowLength + 1 .. $].Print();

    MPI_Barrier(MPI_COMM_WORLD);

    int[] Aresult = new int[Acol.length];
    int[] Bresult = new int[Brow.length];

    MPI_Reduce(cast(void*) Adata, cast(void*) Aresult, cast(int) Adata.length,
            MPI_INT, operation, root, MPI_COMM_WORLD);
    MPI_Reduce(cast(void*) Bdata, cast(void*) Bresult, cast(int) Bdata.length,
            MPI_INT, operation, root, MPI_COMM_WORLD);

    if (rank == root)
    {
        writeln("Results:");
        writeln(Aresult);
        Aresult[rowLength + 1 .. $].Print();

        writeln(Bresult);
        Bresult[rowLength + 1 .. $].Print();
    }

    MPI_Finalize();

    return 0;
}
