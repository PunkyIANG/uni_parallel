module lab4;

import mpi;
import core.runtime : Runtime, CArgs;
import std.stdio : writeln, writefln;
import std.format;

int main()
{
    const int root = 0;
    int size, rank;

    auto args = Runtime.cArgs;
    MPI_Init(&args.argc, &args.argv);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);

    int[] blockCount = [2, 3];

    int[] blockSize = [2, 2];

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

    MPI_Datatype blockPartType;
    MPI_Type_contiguous(blockSize[0], MPI_INT, &blockPartType);
    MPI_Type_commit(&blockPartType);

    MPI_Datatype blockRowType;
    MPI_Type_vector(blockSize[1] * blockCount[0], 1, dimensions[0], blockPartType, &blockRowType);
    MPI_Type_commit(&blockRowType);

    MPI_Datatype extendedBlockRowType;
    int blockRowExtent = blockSize[0] * dimensions[0] * blockCount[0] * blockSize[1] * cast(
        int) int.sizeof;

    if (rank == root)
        writeln("Extent (should be 96): ", blockRowExtent);

    MPI_Type_create_resized(blockRowType, 0, blockRowExtent, &extendedBlockRowType);
    MPI_Type_commit(&extendedBlockRowType);

    MPI_Datatype blockMatrixType;
    MPI_Type_vector(blockCount[1], 1, dimensions[1], extendedBlockRowType, &blockMatrixType);
    MPI_Type_commit(&blockMatrixType);

    long extent, lowerBound;
    MPI_Type_get_extent(blockMatrixType, &lowerBound, &extent);

    int localMatrixSize = blockSize[0] * blockSize[1] * blockCount[0] * blockCount[1];
    int[] testArray = new int[localMatrixSize];

    foreach (index; 0 .. testArray.length)
        testArray[index] = cast(int) index + rank * 1000;
    // testArray[] = rank;

    MPI_Barrier(MPI_COMM_WORLD);
    {
        import core.thread;

        Thread.sleep(dur!"msecs"(20 * rank));
    }

    writeln("Coords: ", coords);

    foreach (int index; 0 .. blockSize[1] * blockCount[1])
        writeln(format("%(%4d %)", testArray[index * blockSize[0] * blockCount[0] .. (
                    index + 1) * blockSize[0] * blockCount[0]]));
    
    MPI_Barrier(MPI_COMM_WORLD);

    if(rank == root)
        writeln("/////////////////////////////");



    MPI_File file;

    int err = MPI_File_open(MPI_COMM_WORLD, cast(char*) "test.txt", MPI_MODE_WRONLY | MPI_MODE_CREATE, MPI_INFO_NULL, &file);

    if (err)
    {
        writeln("File write open error: ", err);
        MPI_Abort(MPI_COMM_WORLD, 911);
    }


    int blockSizeInt = blockSize[0] * blockSize[1];

    int offset = coords[1] * blockSizeInt * dimensions[0] * blockCount[0]
        + coords[0] * blockSize[0];

    offset *= 4;

    MPI_File_set_view(file, offset, MPI_INT, blockMatrixType, cast(char*) "native", MPI_INFO_NULL);

    int intCount = blockSize[0] * blockSize[1] * blockCount[0] * blockCount[1];
    MPI_Status status;

    MPI_File_write(file, testArray.ptr, intCount, MPI_INT, &status);
    MPI_File_close(&file);

    //////////////////////

    err = MPI_File_open(MPI_COMM_WORLD, cast(char*) "test.txt", MPI_MODE_RDONLY | MPI_MODE_DELETE_ON_CLOSE, MPI_INFO_NULL, &file);

    if (err)
    {
        writeln("File read open error: ", err);
        MPI_Abort(MPI_COMM_WORLD, 911);
    }

    int[] fullArray = new int[144];

    // if (rank == root) {
    //     MPI_File_read(file, fullArray.ptr, cast(int)fullArray.length, MPI_INT, &status);

    //     writeln("Read data: ");

    //     int rowLength = dimensions[0] * blockCount[0] * blockSize[0];

    //     foreach (index; 0 .. rowLength)
    //         writeln(format("%(%4d %)", fullArray[index * rowLength .. (
    //                     index + 1) * rowLength]));
    // }

    int[] newCoords = new int[2];
    newCoords[] = coords[];

    newCoords[1]++;

    newCoords[0] += newCoords[1] / dimensions[1];
    newCoords[0] %= dimensions[0];
    newCoords[1] %= dimensions[1];

    offset = newCoords[1] * blockSizeInt * dimensions[0] * blockCount[0]
        + newCoords[0] * blockSize[0];
    offset *= 4;

    MPI_File_set_view(file, offset, MPI_INT, blockMatrixType, cast(char*) "native", MPI_INFO_NULL);

    MPI_File_read(file, testArray.ptr, cast(int) testArray.length, MPI_INT, &status);

    MPI_Barrier(MPI_COMM_WORLD);
    {
        import core.thread;

        Thread.sleep(dur!"msecs"(20 * rank));
    }

    writeln("New coords: ", newCoords);

    foreach (int index; 0 .. blockSize[1] * blockCount[1])
        writeln(format("%(%4d %)", testArray[index * blockSize[0] * blockCount[0] .. (
                    index + 1) * blockSize[0] * blockCount[0]]));

    MPI_File_close(&file);

    int max = 0;

    foreach (int elem; testArray)
        if (elem > max)
            max = elem;
    
    int globalMax = 0;

    MPI_Reduce(&max, &globalMax, 1, MPI_INT, MPI_MAX, root, MPI_COMM_WORLD);

    if (rank == root) 
        writeln("Max: ", globalMax);
    
    MPI_Finalize();
    return 0;
}
