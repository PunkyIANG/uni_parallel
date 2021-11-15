module lab2;

import mpi;
import core.runtime : Runtime, CArgs;
import std.stdio : writeln, writefln;
import std.algorithm : count, countUntil;

int getDimensions(int numNodes, int[] result)
{
    return MPI_Dims_create(numNodes, cast(int) result.length, result.ptr);
}

int main()
{
    const int root = 0;
    int size, rank;

    auto args = Runtime.cArgs;
    MPI_Init(&args.argc, &args.argv);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);

    int[3] dimensions;
    int[3] dimensionLoopsAround;

    MPI_Dims_create(size, cast(int) dimensions.length, dimensions.ptr);

    if (rank == 0)
        writeln("Dimensiunile calculate: ", dimensions);

    int numberOfOnes = cast(int) dimensions[].count(1);

    if (numberOfOnes >= 2)
    {
        writeln("Programul nu poate lucra cu o topologie in forma de linie sau punct");
        writeln("Alegeti un numar de procese ce nu este prim");
        MPI_Finalize();
        return 0;
    }

    MPI_Comm topologyComm;

    MPI_Cart_create(MPI_COMM_WORLD, cast(int) dimensions.length, dimensions.ptr,
            dimensionLoopsAround.ptr, false, &topologyComm);

    int fixedAxisIndex;
    int fixedCoordinate;

    if (numberOfOnes == 1)
    {
        // avem un plan in jurul caruia vom transmite datele
        fixedAxisIndex = cast(int) dimensions[].countUntil(1);
        fixedCoordinate = 0;
    }
    else
    {
        int sideIndex;
        if (rank == root)
        {
            import std.random : uniform;

            sideIndex = uniform!uint % 6;
        }
        MPI_Bcast(&sideIndex, 1, MPI_INT, root, MPI_COMM_WORLD);

        // `sideIndex` will be in range [0..6]
        // for 0, 1 the axis is 0, x
        // for 2, 3 the axis is 1, y
        // for 4, 5 the axis is 2, z 
        fixedAxisIndex = sideIndex / 2;
        // Whether the side is max (or min) along fixedAxisIndex
        bool isMax = sideIndex % 2 == 0;

        fixedCoordinate = isMax ? (dimensions[fixedAxisIndex] - 1) : 0;
    }

    if (rank == root)
        writeln("Am ales axa fixa ", fixedAxisIndex, " cu coordonata ", fixedCoordinate);

    // These two will change as we walk across the edge
    int[2] otherAxes = [(fixedAxisIndex + 1) % 3, (fixedAxisIndex + 2) % 3];

    int[3] coords;
    MPI_Cart_coords(topologyComm, rank, cast(int) coords.length, coords.ptr);

    // return if not on fixed plane
    if (coords[fixedAxisIndex] != fixedCoordinate)
    {
        MPI_Finalize();
        return 0;
    }

    bool isEdge = false;

    foreach (index; 0 .. 3)
    {
        if (index == fixedAxisIndex)
            continue;

        if (coords[index] == 0 || coords[index] == dimensions[index] - 1)
        {
            isEdge = true;
            break;
        }
    }

    // return if is not a corner or edge
    if (!isEdge)
    {
        MPI_Finalize();
        return 0;
    }

    int row = coords[otherAxes[0]];
    int col = coords[otherAxes[1]];

    int[2] otherAxesDims = [dimensions[otherAxes[0]], dimensions[otherAxes[1]]];

    int lastRowIndex = otherAxesDims[0] - 1;
    int lastColIndex = otherAxesDims[1] - 1;

    int[2] GetNextDirection()
    {
        if (row == 0 && col > 0)
            return [0, -1];
        if (row == lastRowIndex && col < lastColIndex)
            return [0, 1];
        if (col == 0 && row < lastRowIndex)
            return [1, 0];
        // else if (col == lastColIndex && row > 0)
        return [-1, 0];

    }

    int[2] GetPrevDirection()
    {
        if (row == 0 && col < lastColIndex)
            return [0, 1];
        if (row == lastRowIndex && col > 0)
            return [0, -1];
        if (col == 0 && row > 0)
            return [-1, 0];
        // else if (col == lastColIndex && row < lastRowIndex)
        return [1, 0];
    }

    // invert the direction if node is at the back (thus fixedCoord is 0)
    // or if the structure is a plane (thus the front side is also the back side) 
    int[2] nextDirection = ((numberOfOnes == 1) | (fixedCoordinate != 0)) ? GetNextDirection()
        : GetPrevDirection();
    int[2] prevDirection = ((numberOfOnes == 1) | (fixedCoordinate != 0)) ? GetPrevDirection()
        : GetNextDirection();

    int[3] nextNodeCoords;
    nextNodeCoords[fixedAxisIndex] = fixedCoordinate;
    nextNodeCoords[otherAxes[0]] = row + nextDirection[0];
    nextNodeCoords[otherAxes[1]] = col + nextDirection[1];

    int[3] prevNodeCoords;
    prevNodeCoords[fixedAxisIndex] = fixedCoordinate;
    prevNodeCoords[otherAxes[0]] = row + prevDirection[0];
    prevNodeCoords[otherAxes[1]] = col + prevDirection[1];

    int getCartesianRank(MPI_Comm comm, const(int)[] coordinates)
    {
        int result;
        MPI_Cart_rank(comm, cast(int*) coordinates.ptr, &result);
        return result;
    }

    int nextRank;
    MPI_Cart_rank(topologyComm, cast(int*) nextNodeCoords.ptr, &nextRank);
    int prevRank;
    MPI_Cart_rank(topologyComm, cast(int*) prevNodeCoords.ptr, &prevRank);

    int sentData = rank;
    int recvData;

    MPI_Sendrecv(&sentData, 1, MPI_INT, nextRank, 451, &recvData, 1, MPI_INT,
            prevRank, 451, MPI_COMM_WORLD, MPI_STATUS_IGNORE);

    {
        import core.thread;

        Thread.sleep(dur!"msecs"(20 * rank));
    }

    writeln("Procesul ", rank, 
            " cu coordonatele ", coords, 
            " a transmis mesajul ", sentData, 
            " la procesul ", nextRank,
            " cu coordonatele ", nextNodeCoords,
            " si a primit mesajul ", recvData,
            " de la procesul ", prevRank,
            " cu coordonatele ", prevNodeCoords);
    
    MPI_Finalize();
    return 0;
}
