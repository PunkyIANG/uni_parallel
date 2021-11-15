module lab1v3;

import mpi;
import core.runtime : Runtime, CArgs;
import std.stdio : writeln, writefln, printf;
import std.algorithm.comparison : min, max;

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

// same as above
int GetRowsPerThread(int rowLength, int size)
{
    return (rowLength + size - 1) / size;
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

void Print(int bitmap)
{
    writefln("%032b", bitmap);
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

int[] CreateDataRow(int[] matrixData, int rowLength, int rank)
{
    int maxRowCountPerThread = cast(int) matrixData.length / rowLength;
    int currentRowCountPerThread = max(min(maxRowCountPerThread,
            rowLength - rank * maxRowCountPerThread), 0);

    int[] result = [rowLength, currentRowCountPerThread];
    int bitmapLength = GetBitmapLength(rowLength);

    int currentThreadDataStart = rank * maxRowCountPerThread;

    foreach (rowId; 0 .. currentRowCountPerThread)
    {
        int[] currentRow = matrixData[rowId * rowLength .. (rowId + 1) * rowLength];
        result = result ~ currentRow ~ new int[bitmapLength];

        result[$ - bitmapLength .. $].SetRow(rowLength, currentThreadDataStart);
        currentThreadDataStart++;
    }

    if (currentRowCountPerThread < maxRowCountPerThread)
        result ~= new int[(rowLength + bitmapLength) * (
                    maxRowCountPerThread - currentRowCountPerThread)];

    return result;
}

int[] InvertBitmap(int[] bitmap, int rowLength)
{
    int[] result = new int[bitmap.length];

    foreach (rowId; 0 .. rowLength)
        foreach (colId; 0 .. rowLength)
        {
            int firstIndex = rowId * rowLength + colId;
            int secondIndex = colId * rowLength + rowId;

            int firstIntIndex = firstIndex / intBitLength;
            int firstBitIndex = firstIndex % intBitLength;

            int secondIntIndex = secondIndex / intBitLength;
            int secondBitIndex = secondIndex % intBitLength;

            if (bitmap[firstIntIndex] & (1 << firstBitIndex))
                result[secondIntIndex] |= 1 << secondBitIndex;
        }

    return result;
}

void Compare(int[] destination, int[] source, int rowLength)
{
    assert(source.length == destination.length);

    int[] matrixRowA = source[0 .. rowLength];
    int[] matrixRowB = destination[0 .. rowLength];

    int[] bitmaskA = source[rowLength .. $];
    int[] bitmaskB = destination[rowLength .. $];

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

    int rowLength = input[0];
    int bitmapLength = GetBitmapLength(rowLength);

    foreach (index; 0 .. min(input[1], output[1]))
    {
        int start = 2 + (rowLength + bitmapLength) * index;
        int end = 2 + (rowLength + bitmapLength) * (index + 1);
        output[start .. end].Compare(input[start .. end], output[0]);
    }

    if (output[1] < input[1])
    {
        int start = 2 + (rowLength + 1) * output[1];

        output[start .. $] = input[start .. $];
        output[1] = input[1];
    }
}

int main()
{
    const int root = 0;
    int size, rank;

    int rowLength = 32;
    int[] A, B;

    auto args = Runtime.cArgs;
    MPI_Init(&args.argc, &args.argv);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);

    if (size == 2)
    {
        writeln("mate, did you really try to use an MPI program on ONE thread? idiot");
        MPI_Finalize();
        return 0;
    }

    MPI_Op operation;
    MPI_Op_create(&SearchMax, 1, &operation);

    int[] Invert(int[] matrix)
    {
        int[] result = new int[matrix.length];

        foreach (rowId; 0 .. rowLength)
            foreach (colId; 0 .. rowLength)
                result[rowId * rowLength + colId] = matrix[colId * rowLength + rowId];

        return result;
    }

    if (rank == root)
    {
        A = new int[rowLength ^^ 2];
        B = new int[rowLength ^^ 2];

        foreach (index; 0 .. rowLength)
        {
            A[index * (rowLength + 1)] = index + 1;
            B[index * (rowLength + 1)] = index + 1;
        }

        // A = [1, 2, 3, 4, 5, 6, 7, 8, 9];

        // B = [10, 11, 12, 13, 14, 15, 16, 17, 18];
        // B = Invert(B);
    }

    int maxRowCountPerThread = GetRowsPerThread(rowLength, size);

    if (rank == root && A.length < rowLength * maxRowCountPerThread * size)
    {
        A ~= new int[rowLength * maxRowCountPerThread * size - A.length];
        B ~= new int[rowLength * maxRowCountPerThread * size - B.length];
    }

    int[] Acol = new int[rowLength * maxRowCountPerThread];
    int[] Brow = new int[rowLength * maxRowCountPerThread];

    MPI_Scatter(A.ptr, rowLength * maxRowCountPerThread, MPI_INT, Acol.ptr,
            rowLength * maxRowCountPerThread, MPI_INT, root, MPI_COMM_WORLD);
    MPI_Scatter(B.ptr, rowLength * maxRowCountPerThread, MPI_INT, Brow.ptr,
            rowLength * maxRowCountPerThread, MPI_INT, root, MPI_COMM_WORLD);

    int[] Adata = Acol.CreateDataRow(rowLength, rank);
    int[] Bdata = Brow.CreateDataRow(rowLength, rank);

    int[] Aresult;
    int[] Bresult;

    if (rank == root)
    {
        Aresult = new int[Adata.length];
        Bresult = new int[Bdata.length];
    }

    MPI_Reduce(cast(void*) Adata, cast(void*) Aresult, cast(int) Adata.length,
            MPI_INT, operation, root, MPI_COMM_WORLD);
    MPI_Reduce(cast(void*) Bdata, cast(void*) Bresult, cast(int) Bdata.length,
            MPI_INT, operation, root, MPI_COMM_WORLD);

    int bitmapLength = GetBitmapLength(rowLength);

    while (maxRowCountPerThread != 1)
    {
        maxRowCountPerThread = GetRowsPerThread(maxRowCountPerThread, size);

        int currentRowCountPerThread = max(min(maxRowCountPerThread,
                rowLength - rank * maxRowCountPerThread), 0);

        int scatterDataLength = (rowLength + bitmapLength) * maxRowCountPerThread;

        Adata = new int[2 + scatterDataLength];
        Bdata = new int[2 + scatterDataLength];

        Adata[0] = rowLength;
        Bdata[0] = rowLength;

        Adata[1] = currentRowCountPerThread;
        Bdata[1] = currentRowCountPerThread;

        if (rank == root)
        {
            if (Aresult[2 .. $].length < scatterDataLength * size)
            {
                Aresult ~= new int[scatterDataLength * size - Aresult[2 .. $].length];
                Bresult ~= new int[scatterDataLength * size - Bresult[2 .. $].length];
            }

            MPI_Scatter(Aresult[2 .. $].ptr, scatterDataLength, MPI_INT,
                    Adata[2 .. $].ptr, scatterDataLength, MPI_INT, root, MPI_COMM_WORLD);
            MPI_Scatter(Bresult[2 .. $].ptr, scatterDataLength, MPI_INT,
                    Bdata[2 .. $].ptr, scatterDataLength, MPI_INT, root, MPI_COMM_WORLD);
        }
        else
        {
            // because Aresult and Bresult are not defined in non root threads
            // slicing them yields a range violation
            // thus we fill the root only parameters with garbage data
            MPI_Scatter(Aresult.ptr, scatterDataLength, MPI_INT,
                    Adata[2 .. $].ptr, scatterDataLength, MPI_INT, root, MPI_COMM_WORLD);
            MPI_Scatter(Bresult.ptr, scatterDataLength, MPI_INT,
                    Bdata[2 .. $].ptr, scatterDataLength, MPI_INT, root, MPI_COMM_WORLD);
        }

        if (rank == root)
        {
            Aresult = new int[Adata.length];
            Bresult = new int[Bdata.length];
        }

        MPI_Reduce(cast(void*) Adata, cast(void*) Aresult,
                cast(int) Adata.length, MPI_INT, operation, root, MPI_COMM_WORLD);
        MPI_Reduce(cast(void*) Bdata, cast(void*) Bresult,
                cast(int) Bdata.length, MPI_INT, operation, root, MPI_COMM_WORLD);
    }

    if (rank == root)
    {
        writeln("Results:");
        writeln(Aresult);

        Aresult[rowLength + 2 .. $].Print();

        Bresult[rowLength + 2 .. $] = Bresult[rowLength + 2 .. $].InvertBitmap(rowLength);
        writeln(Bresult);

        Bresult[rowLength + 2 .. $].Print();

        Aresult[rowLength + 2 .. $] &= Bresult[rowLength + 2 .. $];

        writeln("Final result:");
        Aresult[rowLength + 2 .. $].Print();

        foreach (index; 0 .. rowLength ^^ 2)
        {
            int intIndex = index / intBitLength;
            int bitIndex = index % intBitLength;

            if (Aresult[intIndex + rowLength + 2] & (1 << bitIndex))
                writefln("(%d, %d)", index / rowLength, index % rowLength);
        }
    }

    MPI_Finalize();

    return 0;
}
