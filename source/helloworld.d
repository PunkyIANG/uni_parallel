module helloworld;

import mpi;
import core.runtime : Runtime, CArgs;
import std.stdio : writeln;


int main() {
    int size, rank;

    auto args = Runtime.cArgs;
    MPI_Init(&args.argc, &args.argv);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);

    writeln("hello world! from process with size ", size, " and rank ", rank);

    MPI_Finalize();

    return 0;
}