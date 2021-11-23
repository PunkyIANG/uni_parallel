// =======================================================================
//               Exercitiul 11 (L11Ex4c)
// =======================================================================
// Fie dată o matrice pătratică de orice dimensiune. Să se creeze tipul
// de date care reprezinta elementele de pe diagonala secundară de
// susa matricei. Matricea este iniţializată de procesul cu rankul 0 şi
// prin funcția MPI_Brodcast se transmite acest tip de date tuturor
// proceselor
//
// Пусть задана квадратичная матрица любого размера.
// Создайте тип данных, представляющий элементы на
// диагонале выше главной диагонали матрицы. Матрица
// инициализируется процессом с рангом 0 и через функцию
// MPI_Brodcast этот тип данных передается всем процессам.
// =======================================================================

// Avand o matrice patratica de orice dimensiune, programul dat creeaza
// tipul de date ce reprezinta elementele de pe diagonala mai sus de cea 
// secundara, si o transmite tuturor proceselor prin broadcast
// 
// Matricea initiala:
//  0  1  2  3  4  5  6
//  7  8  9 10 11 12 13
// 14 15 16 17 18 19 20
// 21 22 23 24 25 26 27
// 28 29 30 31 32 33 34
// 35 36 37 38 39 40 41
// 42 43 44 45 46 47 48
//
// Diagonala secundara de sus transmisa:
// -1 -1 -1 -1 -1  5 -1
// -1 -1 -1 -1 11 -1 -1
// -1 -1 -1 17 -1 -1 -1
// -1 -1 23 -1 -1 -1 -1
// -1 29 -1 -1 -1 -1 -1
// 35 -1 -1 -1 -1 -1 -1
// -1 -1 -1 -1 -1 -1 -1
// 

module atestare2;

import mpi;
import core.runtime : Runtime, CArgs;
import std.stdio : writeln, writefln, printf;
import std.format;

int main()
{
    // MPI INIT

    const int root = 0;
    int size, rank;

    auto args = Runtime.cArgs;
    MPI_Init(&args.argc, &args.argv);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);

    if (size < 2) {
        writeln("Lansati programul pe cel putin 2 procese");
        MPI_Finalize();
        return 0;
    }

    // DATA INIT

    int rowLength = 7;
    int[] matrix;

    if (rank == root)
    {
        matrix = new int[rowLength ^^ 2];

        foreach (index; 0 .. matrix.length)
            matrix[index] = cast(int) index;

        writeln("Matricea initiala: ");

        foreach (index; 0 .. rowLength)
            writeln(format("%(%2d %)", matrix[index * rowLength .. (index + 1) * rowLength]));

        writeln();

        /* creeaza matrice de tipul
         0  1  2  3  4  5  6
         7  8  9 10 11 12 13
        14 15 16 17 18 19 20
        21 22 23 24 25 26 27
        28 29 30 31 32 33 34
        35 36 37 38 39 40 41
        42 43 44 45 46 47 48
        */
    }
    else
    {
        matrix = new int[rowLength ^^ 2];
        matrix[] = -1;
    }

    // TYPE

    MPI_Datatype type;

    int[] blocklengths = new int[rowLength - 1];
    blocklengths[] = 1;

    int[] indices = new int[rowLength - 1];
    foreach (index; 0 .. rowLength - 1)
        indices[index] = (rowLength - 2) + index * (rowLength - 1);

    MPI_Type_indexed(rowLength - 1, blocklengths.ptr, indices.ptr, MPI_INT, &type);
    MPI_Type_commit(&type);

    MPI_Bcast(matrix.ptr, 1, type, root, MPI_COMM_WORLD);

    if (rank == 1)
    {
        writeln("Diagonala secundara de sus transmisa: ");

        foreach (index; 0 .. rowLength)
            writeln(format("%(%2d %)", matrix[index * rowLength .. (index + 1) * rowLength]));
    }

    MPI_Finalize();
    return 0;
}
