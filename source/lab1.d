module lab1;

import mpi;
import mpihelper;
import core.runtime : Runtime, CArgs;
import std.stdio : writeln;

const intBitLength = int.sizeof * 8;

// A - coloane
// B - linii

// 0     :0
// 1 ..32:1
// 33..64:2
// basically (bitLen + 31)/32
int GetBitmapLength(int rowLength) {
    int actualLength = rowLength^^2;

    return (actualLength + intBitLength - 1) / intBitLength;
}

void SetBitmapRow(int[] bitmap, rowLength, rowId) {
    assert(bitmap.length == rowLength^^2);
    assert(rowId < rowLength);

    int startPos = rowId * rowLength;
    int endPos = (rowId + 1) * rowLength; //exclusive

    foreach (index; startPos..endPos) {
        int intIndex = index / intBitLength;
        int bitIndex = index % intBitLength;

        bitmap[intIndex] |= 1 << bitIndex;
    }
}


// length, row, bitmap
int[] GetOperationData(int[] row, int rowId) {
    int rowLength = row.length;
    int bitmapLength = GetBitmapLength(rowLength);
    int totalLength = 1 + rowLength + bitmapLength;


}















// output: max, count, firstpos, lastpos
void SearchMax(void* a, void* b, int* len, MPI_Datatype* dt)
{
    int length = *len;
    int[] input  = (cast(int*) a)[0 .. length];
    int[] output = (cast(int*) b)[0 .. 4 * length];

    foreach (index; 0 .. length)
    {
        int currMax = output[4 * index];

        if (input[index] > currMax)
        {
            output[4 * index] = input[index];
            output[4 * index + 1] = 1;
            output[4 * index + 2] = index;
            output[4 * index + 3] = index;
        }
        else if (input[index] == currMax)
        {
            output[4 * index + 1]++;
            output[4 * index + 2];
            output[4 * index + 3] = index;
        }
    }
}

int main()
{
    const int root = 0;
    int size, rank;

    const int rowLength = 3;
    int[] A, B;
    int[] Acol = new int[rowLength], Brow = new int[rowLength];

    auto args = Runtime.cArgs;
    MPI_Init(&args.argc, &args.argv);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);

    if (rank == root)
    {
        A = [2, 0, 1, 1, 2, 0, 0, 1, 2];

        B = [1, 0, 2, 2, 1, 0, 0, 2, 3];
    }

    int[] Invert(int[] matrix)
    {
        int[] result = new int[matrix.length];

        foreach (rowId; 0 .. rowLength)
            foreach (colId; 0 .. rowLength)
                result[rowId * rowLength + colId] = matrix[colId * rowLength + rowId];

        return result;
    }

    // scatter the data:

    MPI_Scatter(&Invert(A).ptr, rowLength, MPI_INT, Acol.ptr, rowLength,
            MPI_INT, root, MPI_COMM_WORLD);
    MPI_Scatter(B.ptr, rowLength, MPI_INT, Brow.ptr, rowLength, MPI_INT, root, MPI_COMM_WORLD);

    MPI_2INT[] Aresult; // index: col; rank: row
    MPI_2INT[] Bresult; // index: row; rank: col

    if (rank == root)
    {
        Aresult = new MPI_2INT[rowLength];
        Bresult = new MPI_2INT[rowLength];
    }

    MPI_Reduce(Acol.ptr, Aresult.ptr, rowLength, MPI_2INT, MPI_MAXLOC, root, MPI_COMM_WORLD);
    MPI_Reduce(Brow.ptr, Bresult.ptr, rowLength, MPI_2INT, MPI_MAXLOC, root, MPI_COMM_WORLD);

    bool[] Amaxmap;
    bool[] Bmaxmap;

    if (rank == root)
    {
        Amaxmap = new bool[rowLength ^^ 2];
        Bmaxmap = new bool[rowLength ^^ 2];

        foreach (row; 0 .. rowLength)
            foreach (col; Aresult[row].rank .. rowLength)
            {

            }

    }

    MPI_Finalize();

    return 0;
}
