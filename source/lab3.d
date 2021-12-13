module lab3;

import mpi;
import core.runtime : Runtime, CArgs;
import std.stdio : writeln, writefln;
import std.format;

int ceilingDiv(int a, int b)
{
    return (a + b - 1) / b;
}

int main()
{
    const int root = 0;
    int size, rank;

    auto args = Runtime.cArgs;
    MPI_Init(&args.argc, &args.argv);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);

    int[] matrixSize = [9, 9];

    int[] blockSize = [2, 2];

    int[] fullMatrix;

    if (rank == root)
    {
        fullMatrix = new int[matrixSize[0] * matrixSize[1]];

        foreach (index; 0 .. fullMatrix.length)
            fullMatrix[index] = cast(int) index;

        // import std.random : uniform;
        // import std.array : array;
        // import std.range : generate, takeExactly;

        // fullMatrix = generate!(() => uniform(0, 100)).takeExactly(
        //     matrixSize[0] * matrixSize[1]).array;
        // writeln(fullMatrix.length);
        // writeln(fullMatrix[0 .. matrixSize[0]]);
        // assert(fullMatrix[0] >= 0 && fullMatrix[0] < 100);

        foreach (index; 0 .. matrixSize[1])
            writeln(format("%(%2d %)", fullMatrix[index * matrixSize[0] .. (index + 1) * matrixSize[0]]));

    }

    int[2] dimensions;
    int[2] dimensionLoopsAround;

    MPI_Dims_create(size, cast(int) dimensions.length, dimensions.ptr);

    if (rank == 0)
        writeln("Dimensiunile calculate: ", dimensions);

    MPI_Comm topologyComm;

    MPI_Cart_create(MPI_COMM_WORLD, cast(int) dimensions.length, dimensions.ptr,
        dimensionLoopsAround.ptr, false, &topologyComm);

    int[2] coords;
    MPI_Cart_coords(topologyComm, rank, cast(int) coords.length, coords.ptr);

    // writeln(coords, " ", rank);

    int blockSpace = blockSize[0] * blockSize[1];

    int[] blocksPerAxis = new int[dimensions.length];
    int localBlockCount = 1;

    foreach (index; 0 .. dimensions.length)
    {
        blocksPerAxis[index] = matrixSize[index].ceilingDiv(blockSize[index] * dimensions[index]);
        localBlockCount *= blocksPerAxis[index];
    }

    int[] paddedMatrix;
    int[2] paddedDimensions;

    foreach (index; 0 .. paddedDimensions.length)
    {
        paddedDimensions[index] = blocksPerAxis[index] * blockSize[index] * dimensions[index];
    }

    MPI_Win window;

    if (rank == root)
    {
        writeln("Blocuri per axa: ", blocksPerAxis);
        writeln("Dimensiuni cu padding: ", paddedDimensions);

        // expand the matrix
        paddedMatrix = new int[paddedDimensions[0] * paddedDimensions[1]];
        paddedMatrix[] = -1;

        foreach (int index; 0 .. matrixSize[1])
        {
            paddedMatrix[index * paddedDimensions[0] .. index * paddedDimensions[0] + matrixSize[0]] =
                fullMatrix[index * matrixSize[0] .. (index + 1) * matrixSize[0]];
        }

        foreach (index; 0 .. paddedDimensions[1])
            writeln(format("%(%2d %)", paddedMatrix[index * paddedDimensions[0] .. (
                        index + 1) * paddedDimensions[0]]));

        MPI_Win_create(paddedMatrix.ptr, int.sizeof * paddedMatrix.length, int.sizeof, MPI_INFO_NULL, MPI_COMM_WORLD, &window);
    }
    else
    {
        MPI_Win_create(paddedMatrix.ptr, 0, int.sizeof, MPI_INFO_NULL, MPI_COMM_WORLD, &window);
    }

    MPI_Win_fence(0, window);

    int[] localMatrix = new int[localBlockCount * blockSpace];

    foreach (blockYIndex; 0 .. blocksPerAxis[1])
        foreach (blockXIndex; 0 .. blocksPerAxis[0])
            foreach (blockRow; 0 .. blockSize[1])
            {
                int localBlockRowIndex = blockYIndex * blocksPerAxis[0] * blockSpace
                    + blockRow * blocksPerAxis[0] * blockSize[0]
                    + blockXIndex * blockSize[0];

                int globalBlockRowIndex = blockYIndex * paddedDimensions[0] * blockSize[1] * dimensions[1]
                    + coords[1] * paddedDimensions[0] * blockSize[1]

                    + blockRow * paddedDimensions[0]

                    + blockXIndex * blockSize[0] * dimensions[0]
                    + coords[0] * blockSize[0];

                MPI_Get(&localMatrix[localBlockRowIndex], blockSize[0], MPI_INT, root, globalBlockRowIndex, blockSize[0], MPI_INT, window);
                MPI_Win_fence(0, window);
            }

    MPI_Barrier(MPI_COMM_WORLD);

    {
        import core.thread;

        Thread.sleep(dur!"msecs"(20 * rank));
    }

    writeln("Local matrix w/ coords ", coords, " and rank ", rank, ": ");

    int[] localMatrixDimensions = [
        blocksPerAxis[0] * blockSize[0], blocksPerAxis[1] * blockSize[1]
    ];

    foreach (index; 0 .. localMatrixDimensions[1])
        writeln(format("%(%2d %)", localMatrix[index * localMatrixDimensions[0] .. (
                    index + 1) * localMatrixDimensions[0]]));

    MPI_Win_free(&window);

    MPI_Finalize();
    return 0;
}
