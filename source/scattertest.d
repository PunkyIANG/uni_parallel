module scattertest;

import mpi;

import core.runtime : Runtime, CArgs;
import std.stdio : writeln, writefln;

int main()
{
    const int root = 0;
    int size, rank;
    int[] A;

    auto args = Runtime.cArgs;
    MPI_Init(&args.argc, &args.argv);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);

    if (rank == root)
    {
        A = new int[25];
        foreach (index; 0 .. A.length)
            A[index] = cast(int)index;
    }

    int[] receivedData;

    if (rank == 2) {
        receivedData = new int[5];
    } else {
        receivedData = new int[10];
    }

    MPI_Scatter(A.ptr, 10, MPI_INT, receivedData.ptr, 10, MPI_INT, root, MPI_COMM_WORLD);

    writeln(receivedData);




    MPI_Finalize();

    return 0;

}
