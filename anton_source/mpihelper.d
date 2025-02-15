module mpihelper;

import mpi;

// // Disable trapping. MPI does not play well with those.
// extern(C) __gshared string[] rt_options = [ "trapExceptions=0" ];

struct GroupInfo
{
    /// The number of processes in the group
    int size;
    /// The rank of the current process within the group
    int rank;

    /// Checks if the currect process is part of this group
    bool belongs() { return rank != MPI_UNDEFINED; }
}

import core.runtime : Runtime, CArgs;

struct InitInfo
{
    /// Represents the properties of the COMM_WORLD group
    GroupInfo groupInfo;
    alias groupInfo this;

    CArgs args;
}

InitInfo initialize()
{
    InitInfo result;
    with (result)
    {
        args = Runtime.cArgs;
        MPI_Init(&args.argc, &args.argv);
        MPI_Comm_size(MPI_COMM_WORLD, &size);
        MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    }
    return result;
}

void finalize()
{
    MPI_Finalize();
}

struct ProcessorName
{
    char[MPI_MAX_PROCESSOR_NAME] _buffer;
    int _size;
    inout(char)[] get() @property inout { return _buffer[0.._size]; }
    alias get this;
}

ProcessorName getProcessorName()
{
    ProcessorName result;
    MPI_Get_processor_name(result._buffer.ptr, &result._size);
    return result;
}

// We need this overload because MPI_COMM_WORLD is not a compile-time known constant.
// void barrier() { barrier(MPI_COMM_WORLD); }
void barrier(MPI_Comm comm = MPI_COMM_WORLD) { MPI_Barrier(comm); }

enum MPI_Datatype INVALID_DATATYPE = null;

// TODO: a more complete list of these
enum Pair;

@Pair struct IntInt
{
    int value;
    int rank;
}

@Pair struct DoubleInt
{
    double value;
    int rank;
}

template Datatype(T)
{
    static if (is(T == int))
        alias Datatype = MPI_INT;
    else static if (is(T == uint))
        alias Datatype = MPI_UNSIGNED;
    else static if (is(T == float))
        alias Datatype = MPI_FLOAT;
    else static if (is(T == double))
        alias Datatype = MPI_DOUBLE;
    else static if (is(T == IntInt))
        alias Datatype = MPI_2INT;
    else static if (is(T == DoubleInt))
        alias Datatype = MPI_DOUBLE_INT;
    else static if (IsCustomDatatype!T)
    {
        __gshared MPI_Datatype Datatype = INVALID_DATATYPE;
    }
    else static assert(0, "Invalid datatype: "~T.stringof);
}

enum IsCustomDatatype(T) = is(T : TElement[N], TElement, size_t N) || is(T == struct);
enum IsValidDatatype(T) = is(T : int) || is(T : double) || is(T == uint) 
    || is(T == IntInt) || is(T == DoubleInt) || IsCustomDatatype!T;

// Must have a getter to allow AliasSeq to work.
MPI_Datatype getDatatypeId(T)()
{
    assert(Datatype!T != INVALID_DATATYPE);
    return Datatype!T;
}

MPI_Datatype createDatatype(T : TElement[N], TElement, size_t N)()
{
    MPI_Type_contiguous(cast(int) N, Datatype!TElement, &(Datatype!T));
    MPI_Type_commit(&(Datatype!T));
    return Datatype!T;
}

MPI_Datatype createDatatype(T)() if (is(T == struct))
{
    assert(Datatype!T == INVALID_DATATYPE);

    // We fill these completely in all cases.
    int[T.tupleof.length] counts = void;
    MPI_Aint[T.tupleof.length] offsets = void;
    MPI_Datatype[T.tupleof.length] datatypes = void;

    size_t index = 0;
    static foreach (t; T.tupleof)
    {{
        alias typeId = Datatype!(typeof(t));

        // If it's not a builtin type, create the type.
        // I'm not sure if I should do it like this or not.
        // Another thing, circular dependencies are obviously not allowed.
        static if (IsCustomDatatype!(typeof(t)))
        {
            if (typeId == INVALID_DATATYPE)
                .createDatatype!(typeof(t));
            assert(typeId != INVALID_DATATYPE);
        }

        datatypes[index] = typeId;
        offsets[index] = cast(MPI_Aint) t.offsetof;
        counts[index] = 1;
        index++;
    }}

    MPI_Type_create_struct(cast(int) T.tupleof.length, counts.ptr, offsets.ptr, datatypes.ptr, &(Datatype!T));
    MPI_Type_commit(&(Datatype!T));
    return Datatype!T;
}

// size_t getDatatypeSize(T)(T type)
// {
//      if (is(type

template BufferInfo(alias buffer)
{
    static if (is(typeof(buffer) : T[], T))
    {
        T* ptr() { return buffer.ptr; }
        int length() { return cast(int) buffer.length; }
    }
    else static if (is(typeof(buffer) == T*, T))
    {
        T* ptr() { return buffer; }
        int length() { return 1; }
    }
    else static assert(0, "Type `" ~ typeof(buffer).stringof ~ "` must be a pointer or a slice.");
    
    alias ElementType = typeof(buffer[0]);
    auto datatype() { return getDatatypeId!ElementType; }
}

/// Unrolls a buffer argument (an array or a pointer to an element) 
/// into a sequence of pointer, length and mpi type.
template UnrollBuffer(alias buffer)
{
    alias Info = BufferInfo!buffer;
    import std.meta : AliasSeq;
    alias UnrollBuffer = AliasSeq!(Info.ptr, Info.length, Info.datatype); 
}

/// Buffer can be either a slice or a pointer to the single element.
int send(T)(T buffer, int dest, int tag, MPI_Comm comm = MPI_COMM_WORLD)
{
    return MPI_Send(UnrollBuffer!buffer, dest, tag, comm);
}

/// ditto
int recv(T)(T buffer, int source, int tag, MPI_Status* status = MPI_STATUS_IGNORE, MPI_Comm comm = MPI_COMM_WORLD)
{
    return MPI_Recv(UnrollBuffer!buffer, source, tag, comm, status);
}

/// ditto
int sendRecv(T, U)(
    T sendBuffer, int dest, int sendtag, 
    U recvBuffer, int source, int recvtag, 
    MPI_Status* status = MPI_STATUS_IGNORE, MPI_Comm comm = MPI_COMM_WORLD)
{
    return MPI_Sendrecv(
        UnrollBuffer!sendBuffer, dest,   sendtag, 
        UnrollBuffer!recvBuffer, source, recvtag, 
        comm, status);
}

/// ditto
int bcast(T)(T buffer, int root, MPI_Comm comm = MPI_COMM_WORLD)
{
    return MPI_Bcast(UnrollBuffer!buffer, root, comm);
}

private enum gatherTag = 717;

/// https://www.mpi-forum.org/docs/mpi-4.0/mpi40-report.pdf#page=237&zoom=180,55,524
int intraGatherSend(T)(T buffer, int root, MPI_Comm comm = MPI_COMM_WORLD)
{
    return send(buffer, root, gatherTag, comm);
}

/// This should be called by the root process to receive messages from the processes that called `gatherSend()`
/// into the buffer. The rank in InitInfo must correspond to the root rank specified in the `gatherSend()` calls.
/// It will most likely hang infinitely otherwise.
void intraGatherRecv(T)(T[] buffer, in InitInfo info, MPI_Comm comm = MPI_COMM_WORLD)
{
    size_t currentReceiveIndex = 0;
    size_t singleReceiveSize = buffer.length / (info.size - 1);

    assert(buffer.sizeof >= singleReceiveSize);

    foreach (i; info.size)
    {
        if (i != info.rank)
        {
            recv(buffer[currentReceiveIndex .. currentReceiveIndex + singleReceiveSize], i, gatherTag, MPI_STATUS_IGNORE, comm);
            currentReceiveIndex += singleReceiveSize;
        }
    }
} 

/// This is a stupid function because it assumes non-root processes also allocate the array
/// which is just wrong. But otherwise it makes all processes compute what the root would compute.
/// Gather is just meaningless imo.
int gather(T, U)(T sendBuffer, U[] recvBuffer, int root, int groupSize, MPI_Comm comm = MPI_COMM_WORLD)
{
    alias sendBufferInfo = BufferInfo!sendBuffer;
    
    // Make sure the recv buffer can hold all input of all processes combined.
    assert(recvBuffer.length / groupSize >= sendBufferInfo.length);
    // The types must match.
    static assert(__traits(isSame, sendBufferInfo.datatype, Datatype!U));

    return MPI_Gather(UnrollBuffer!sendBuffer, recvBuffer.ptr, sendBufferInfo.length, sendBufferInfo.datatype, root, comm);
}

/// `nullOrReceive` must be the size of the communicator group if `root == myrank`, otherwise it can be null.
/// This is stupid since one parameter is superfluous most of the time.
int gatherNoAlloc(T, U)(T sendBuffer, U[] nullOrReceive, int root, int myrank, MPI_Comm comm = MPI_COMM_WORLD)
{
    alias sendBufferInfo = BufferInfo!sendBuffer;
    static assert(__traits(isSame, sendBufferInfo.datatype, Datatype!U));

    if (root == myrank)
    {
        // Must be receiving.
        assert(nullOrReceive);

        return MPI_Gather(
            sendBufferInfo.ptr, sendBufferInfo.length, Datatype!T, 
            nullOrReceive.ptr,  sendBufferInfo.length, Datatype!T,
            root, comm);
    }
    return MPI_Gather(
        sendBufferInfo.ptr, sendBufferInfo.length, Datatype!T,
        // TODO: this should work with dummy values too, i.e. zeros.
        // https://www.mpi-forum.org/docs/mpi-4.0/mpi40-report.pdf#page=236&zoom=180,65,600
        // "significant only at root".
        null, sendBufferInfo.length, Datatype!T,
        root, comm);
}

// template ElementType(T)
// {
//     static if (is(T : E[], E) || is(T : E*, E))
//         alias ElementType = E;
//     else static assert(0);
// }
// template ElementType(alias buffer)
// {
//     alias ElementType = typeof(buffer[0]);
// }

/// Allocates `receiveBuffer` if `root` == the rank of the current process. 
/// Executes gather after that. This function makes it impossible to make mistakes with the size of the buffer.
/// If the buffer is already allocated, prefer `gatherNoAlloc()`.
int gatherWithAlloc(T, U)(T sendBuffer, out U[] receiveBuffer, int root, in InitInfo info, MPI_Comm comm = MPI_COMM_WORLD)
{
    alias sendBufferInfo = BufferInfo!sendBuffer;
    static assert(__traits(isSame, sendBufferInfo.ElementType, U));

    if (root == info.rank)
    {
        receiveBuffer = new U[](sendBufferInfo.length * info.size);
        return MPI_Gather(UnrollBuffer!sendBuffer, 
            receiveBuffer.ptr, sendBufferInfo.length, sendBufferInfo.datatype, 
            root, comm);
    }

    return MPI_Gather(UnrollBuffer!sendBuffer, null, sendBufferInfo.length, sendBufferInfo.datatype, root, comm);
}


/// Does an inplace scatter as the root process - the process' share of buffer is left in the buffer
int intraScatterSend(T)(T buffer, in InitInfo info, MPI_Comm comm = MPI_COMM_WORLD)
{
    alias sendBufferInfo = BufferInfo!buffer;
    return MPI_Scatter(sendBufferInfo.ptr, sendBufferInfo.length / info.size, sendBufferInfo.datatype,
        MPI_IN_PLACE, 0, null, info.rank, comm);
}

/// Receives data from the root process using MPI_Scatter
int intraScatterRecv(T)(T buffer, int root, MPI_Comm comm = MPI_COMM_WORLD)
{
    return MPI_Scatter(null, 0, null, UnrollBuffer!buffer, root, comm);
}

/// Gets data from all processes into the `recvBuffer` using MPI_Allgather.
/// The buffer is assumed to be long enough to hold data gathered form all other processes,
/// more precisely, `sendBuffer.length * groupSize`.
int allgather(T, U)(const(T) sendBuffer, U[] recvBuffer, MPI_Comm comm = MPI_COMM_WORLD) 
{
    alias sendBufferInfo = BufferInfo!sendBuffer;
    static assert(is(sendBufferInfo.ElementType == U));
    return MPI_Allgather(UnrollBuffer!sendBuffer, recvBuffer.ptr, 
        sendBufferInfo.length, sendBufferInfo.datatype, comm);
}

/// Gets data from all processes into `recvBuffer`, returned as the second argument.
int allgatherAlloc(T, U)(const(T) sendBuffer, out U[] recvBuffer, int groupSize, MPI_Comm comm = MPI_COMM_WORLD) 
{
    alias sendBufferInfo = BufferInfo!sendBuffer;
    static assert(is(sendBufferInfo.ElementType == U));
    recvBuffer = new U[](groupSize * sendBufferInfo.length);
    return MPI_Allgather(UnrollBuffer!sendBuffer, recvBuffer.ptr, 
        sendBufferInfo.length, sendBufferInfo.datatype, comm);
}

template OperationInfo(alias operation, bool _IsUserDefined = true)
{
    enum IsUserDefined = _IsUserDefined;
    static if (is(typeof(&operation) : void function(T*, T*, int*), T))
    {
        enum HasRequiredType = true;
        alias RequiredType = T;
        static void func(void* invec, void* inoutvec, int* length, MPI_Datatype* datatype)
        {
            return operation(cast(T*) invec, cast(T*) inoutvec, length);
        }
    }
    else static if (is(typeof(&operation) : void function(T*, T*, int), T))
    {
        enum HasRequiredType = true;
        alias RequiredType = T;
        static void func(void* invec, void* inoutvec, int* length, MPI_Datatype* datatype)
        {
            return operation(cast(T*) invec, cast(T*) inoutvec, *length);
        }
    }
    else static if (is(typeof(&operation) : void function(T[], T[]), T))
    {
        enum HasRequiredType = true;
        alias RequiredType = T;
        static void func(void* invec, void* inoutvec, int* length, MPI_Datatype* datatype)
        {
            return operation((cast(T*) invec)[0..*length], (cast(T*) inoutvec)[0..*length]);
        }
    }
    else
    {
        enum HasRequiredType = false;
        static void func(void* invec, void* inoutvec, int* length, MPI_Datatype* datatype)
        {
            return operation(invec, inoutvec, length, datatype);
        }
    }
}

struct Operation(alias operation)
{
    static if (is(operation == function))
    {
        MPI_Op handle;
        mixin OperationInfo!operation;
    }
    // TODO: add the ability to wrap these in with types.
    else
    {
        static MPI_Op handle() { return operation; }
        enum HasRequiredType = false;
        enum IsUserDefined = false;
    }
}


// https://www.open-mpi.org/doc/v3.0/man3/MPI_Reduce_local.3.php
// MPI_MAX             maximum
// MPI_MIN             minimum
// MPI_SUM             sum
// MPI_PROD            product
// MPI_LAND            logical and
// MPI_BAND            bit-wise and
// MPI_LOR             logical or
// MPI_BOR             bit-wise or
// MPI_LXOR            logical xor
// MPI_BXOR            bit-wise xor
// MPI_MAXLOC          max value and location
// MPI_MINLOC          min value and location
alias    opMax = Operation!MPI_MAX;
alias    opMin = Operation!MPI_MIN;
alias    opSum = Operation!MPI_SUM;
alias   opProd = Operation!MPI_PROD;
alias   opLand = Operation!MPI_LAND;
alias   opBand = Operation!MPI_BAND;
alias    opLor = Operation!MPI_LOR;
alias    opBor = Operation!MPI_BOR;
alias   opLxor = Operation!MPI_LXOR;
alias   opBxor = Operation!MPI_BXOR;
alias opMaxloc = Operation!MPI_MAXLOC;
alias opMinloc = Operation!MPI_MINLOC;

auto createOp(alias operation)(int commute) 
{
    Operation!operation op;
    MPI_Op_create(&(op.func), commute, &(op.handle));
    return op;
}

int freeOp(Op)(Op op)
{
    return MPI_Op_free(&(op.handle));
}

// /// Op must be duck-compatible with Operation!func.
// int intraReduceSend(T, Op)(T buffer, Op op, int root, MPI_Comm comm = MPI_COMM_WORLD)
// {
//     alias bufferInfo = BufferInfo!buffer;
//     static if (Op.HasRequiredType)
//         static assert(is(bufferInfo.ElementType == Op.RequiredType));
//     return MPI_Reduce(bufferInfo.ptr, null, bufferInfo.length, bufferInfo.datatype, op.handle, root, comm);
// }

// /// Must be called by root.
// int intraReduceRecv(T, Op)(T buffer, Op op, int root, MPI_Comm comm = MPI_COMM_WORLD)
// {
//     alias bufferInfo = BufferInfo!buffer;
//     static if (Op.HasRequiredType)
//         static assert(is(bufferInfo.ElementType == Op.RequiredType));
//     return MPI_Reduce(bufferInfo.ptr, MPI_IN_PLACE, bufferInfo.length, bufferInfo.datatype, op.handle, root, comm);
// }

int intraReduce(T, Op)(T buffer, Op op, int rank, int root, MPI_Comm comm = MPI_COMM_WORLD)
{
    alias bufferInfo = BufferInfo!buffer;
    
    MPI_Op opHandle;
    static if (__traits(hasMember, op, "handle"))
    {
        static assert(!Op.HasRequiredType || is(bufferInfo.ElementType == Op.RequiredType));
        opHandle = op.handle;
    }
    else
    {
        opHandle = op;
    }
    
    return MPI_Reduce(rank == root ? MPI_IN_PLACE : bufferInfo.ptr, UnrollBuffer!buffer, opHandle, root, comm);
}

void abortIf(bool condition, lazy string message = null, MPI_Comm comm = MPI_COMM_WORLD)
{
    if (condition)
    {
        import std.stdio : writeln;
        writeln("The process has been aborted: ", message);
        MPI_Abort(comm, 1);
    }
}

// Process 0 gets the result (the values array gets mutated).
// The input values array most likely will be mutated.
// Assumes op is commutative.
void customIntraReduce(T)(T[] values, in InitInfo info, void delegate(const(T)[] input, T[] inputOutput) op)
{
    int processesLeft = info.size;
    const tag = 15;

    // Only half of the processes will be getting values.
    T[] recvBuffer;
    if (info.rank <= info.size / 2)
        recvBuffer = new T[](values.length);

    while (processesLeft > 1)
    {
        // Examples:
        // 0, 1, 2 -> (0, 2), (1, _)        gap = 2, numActive = 2
        // 0, 1, 2, 3 -> (0, 2), (1, 3)     gap = 2, numActive = 2
        // 0, 1 -> (0, 1)                   gap = 1, numActive = 1

        // Round up
        int activeProcessesCount = (processesLeft + 1) / 2;

        // If there's an odd number of processes, the last active does nothing
        if ((processesLeft & 1) && info.rank == activeProcessesCount - 1)
        {
            processesLeft = activeProcessesCount;
            continue;
        }

        // We're the first process (the active one) in a group
        if (info.rank < activeProcessesCount)
        {
            // Skip over other processes.
            int partnerId = activeProcessesCount + info.rank;
            mh.recv(recvBuffer, partnerId, tag);
            // Values now contain the result of the operation.
            op(recvBuffer, values);
        }
        // We're the second process in a group
        else
        {
            int partnerId = info.rank - activeProcessesCount;
            mh.send(values, partnerId, tag);
            break;
        }

        processesLeft = activeProcessesCount;
    }
}

private template UnrollMemoryAccess(alias buffer, alias startIndex, alias targetRank)
{
    alias bufferInfo = BufferInfo!buffer;
    MPI_Aint offset() { return cast(MPI_Aint) (startIndex * bufferInfo.ElementType.sizeof); }
    import std.meta : AliasSeq;
    alias UnrollMemoryAccess = AliasSeq!(UnrollBuffer!buffer, targetRank, offset, bufferInfo.length, bufferInfo.datatype);
}

/// A wrapper for an RMA window, useful for calling RMA routines
struct MemoryWindow(T)
{
    MPI_Win handle;

    int get(Buffer)(Buffer recvBuffer, size_t startIndex, int targetRank)
    {
        static assert(is(BufferInfo!recvBuffer.ElementType == T)); 
        return MPI_Get(UnrollMemoryAccess!(recvBuffer, startIndex, targetRank), handle);
    }

    int put(Buffer)(Buffer sendBuffer, size_t startIndex, int targetRank)
    {
        static assert(is(BufferInfo!sendBuffer.ElementType == T)); 
        return MPI_Put(UnrollMemoryAccess!(sendBuffer, startIndex, targetRank), handle);
    }

    private MPI_Op getOpHandleWithChecks(Op)(Op op)
    {
        static if (is(Op == MPI_Op))
        {
            return op;
        }
        else
        {
            // https://www.mpi-forum.org/docs/mpi-4.0/mpi40-report.pdf#page=618&zoom=180,19,455
            static assert(!Op.IsUserDefined);

            static assert(!Op.HasRequiredType || is(T == Op.RequiredType));
            return op.handle;
        }
    }

    /// Writes `buffer` to the target, applying `op` on the input and output vectors
    /// before writing to the destination.
    /// `op` must be one of the predefined operations or MPI_REPLACE.
    int accumulate(Buffer, Op)(Buffer buffer, size_t startIndex, int targetRank, Op op)
    {
        static assert(is(BufferInfo!buffer.ElementType == T)); 
        return MPI_Accumulate(
            UnrollMemoryAccess!(buffer, startIndex, targetRank), 
            getOpHandleWithChecks(op), handle); 
    }

    /// Returns the data in the destination buffer before applying the accumulation.
    /// The same set of restrictions applies to this function as to `accumulate`.
    /// MPI_NO_OP may be used as the values of `op`.
    int getAccumulate(Buffer, Op)(Buffer buffer, size_t startIndex, int targetRank, Op op)
    {
        static assert(is(BufferInfo!buffer.ElementType == T)); 
        return MPI_Get_accumulate(
            UnrollMemoryAccess!(buffer, startIndex, targetRank), 
            getOpHandleWithChecks(op), handle); 
    }

    int fetchAndOp(Op)(T* value, T* destinationBeforeOp, size_t startIndex, int targetRank, Op op)
    {
        return MPI_Fetch_and_op(
            value, destinationBeforeOp, Datatype!T, 
            targetRank, 
            cast(MPI_Aint) (startIndex * T.sizeof), 
            getOpHandleWithChecks(op), handle);
    }

    version (MPINotAncient)
    {
        int compareAndSwap(
            T* replacement, T* compareAgainst, T* destinationBeforeSwap, 
            size_t startIndex, int targetRank)
        {
            static assert(!IsCustomDatatype!T);

            return MPI_Compare_and_swap(
                replacement, compareAgainst, destinationBeforeSwap, 
                Datatype!T, targetRank, cast(MPI_Aint) (startIndex * T.sizeof), 
                handle);
        }
    }

    // T getSync(size_t index = 0)
    // {
    //     T result;
    // }

    void free()
    {
        MPI_Win_free(&handle);
    }

    void fence(int modeFlags = 0)
    {
        MPI_Win_fence(modeFlags, handle);
    }
}

/// Create a wrapper for an RMA window, backed by a buffer
auto createMemoryWindow(Buffer)(Buffer buffer, MPI_Info info = MPI_INFO_NULL, MPI_Comm comm = MPI_COMM_WORLD)
{
    alias bufferInfo = BufferInfo!buffer;
    MemoryWindow!(bufferInfo.ElementType) window = void;
    MPI_Win_create(
        bufferInfo.ptr, bufferInfo.ElementType.sizeof * bufferInfo.length, 1, 
        info, comm, &(window.handle));
    return window;
}

/// Create a wrapper for an RMA window, which is not backed up by a buffer.
/// This means other processes will not be able to read from this process' memory.
/// Typically used for reading other process' memory.
auto acquireMemoryWindow(ElementType)(MPI_Info info = MPI_INFO_NULL, MPI_Comm comm = MPI_COMM_WORLD)
{
    MemoryWindow!ElementType result = void;
    MPI_Win_create(MPI_BOTTOM, 0, 1, info, comm, &(result.handle));
    return result;
}

auto allocateMemoryWindow(T)(MPI_Aint length, out T[] allocatedBuffer, 
    MPI_Info info = MPI_INFO_NULL, MPI_Comm comm = MPI_COMM_WORLD)
{
    MemoryWindow!T window = void;
    void* memory;
    MPI_Win_allocate(length * T.sizeof, 1, info, comm, &memory, &(window.handle));
    allocatedBuffer = (cast(T*) memory)[0..length];
    return window;
}

void freeMemory(T)(T* memory)
{
    MPI_Free_mem(memory);
}

int readInt()
{
    import std.stdio : readln, stdin;
    import std.conv : to;
    import std.string : strip;
    while (true)
    {
        try
        {
            return readln().strip.to!int;
        }
        catch (Exception err)
        {
        }
    }
    return 0;
}

MPI_Group getGroup(MPI_Comm comm = MPI_COMM_WORLD)
{
    MPI_Group group;
    MPI_Comm_group(comm, &group);
    return group;
}

GroupInfo getGroupInfo(MPI_Group group)
{
    GroupInfo result;
    MPI_Group_size(group, &result.size);
    MPI_Group_rank(group, &result.rank);
    return result;
}

MPI_Group createGroupInclude(MPI_Group baseGroup, int[] includedRanks)
{
    MPI_Group result;
    MPI_Group_incl(baseGroup, cast(int) includedRanks.length, includedRanks.ptr, &result);
    return result;
}

MPI_Group createGroupExclude(MPI_Group baseGroup, int[] excludedRanks)
{
    MPI_Group result;
    MPI_Group_excl(baseGroup, cast(int) excludedRanks.length, excludedRanks.ptr, &result);
    return result;
}

void free(MPI_Group* group)
{
    MPI_Group_free(group);
}

void free(MPI_Comm* comm)
{
    MPI_Comm_free(comm);
}

MPI_Comm createComm(MPI_Comm baseComm, MPI_Group baseGroup)
{
    MPI_Comm result;
    MPI_Comm_create(baseComm, baseGroup, &result);
    return result;
}

/// `dimensionLengths` — number of processes for each dimension.
MPI_Comm createCartesianTopology(
    int[] dimensionLengths, int[] dimensionLoopsAround, MPI_Comm baseComm = MPI_COMM_WORLD, bool reorder = false)
{
    assert(dimensionLengths.length == dimensionLoopsAround.length);
    MPI_Comm result;
    int reorderInt = cast(int) reorder;
    MPI_Cart_create(
        baseComm, 
        cast(int) dimensionLengths.length, dimensionLengths.ptr, 
        dimensionLoopsAround.ptr, reorderInt, &result);
    return result;
}

int getDimensions(int numNodes, int[] result)
{
    return MPI_Dims_create(numNodes, cast(int) result.length, result.ptr);
}

/// `indices` contain the ending index one past the end of the last edge index for the given node.
/// `edges` is a flat arry of neighbors for nodes.
/// For example, a call like `createGraph([2, 3, 4], [1, 2, 0, 0])` creates the graph
///      ( 1 ) <—> ( 0 ) <—> ( 2 )
/// The parameters are assumed to have valid values, 
/// since the return code of the underlying function is ignored.
MPI_Comm createGraph(const(int)[] indices, const(int)[] edges, MPI_Comm baseComm = MPI_COMM_WORLD, bool reorder = false)
{
    assert(indices[$ - 1] == edges.length);
    MPI_Comm result;
    int reorderInt = cast(int) reorder;
    // They are const in the spec, but not const in the bindings for some reason?
    MPI_Graph_create(baseComm, cast(int) indices.length, cast(int*) indices.ptr, cast(int*) edges.ptr, reorderInt, &result);
    return result;
}


version (MPINotAncient)
{
    private int* getWeightsPointer(const(int)[] weights)
    {
        // https://www.mpi-forum.org/docs/mpi-4.0/mpi40-report.pdf#page=438&zoom=180,65,231
        return weights.length == 0 ? (cast(int*) MPI_WEIGHTS_EMPTY) : (cast(int*) weights.ptr);
    }

    MPI_Comm createDistributedGraphFromAdjacencies(
        const(int)[] incomingEdges, const(int)[] incomingEdgeWeights,
        const(int)[] outgoingEdges, const(int)[] outgoingEdgeWeights,
        MPI_Comm baseComm = MPI_COMM_WORLD, bool reorder = false, MPI_Info info = MPI_INFO_NULL)
    {
        assert(incomingEdges.length == incomingEdgeWeights.length);
        assert(outgoingEdges.length == outgoingEdgeWeights.length);
        MPI_Comm result;
        int reorderInt = cast(int) reorder;
        MPI_Dist_graph_create_adjacent(
            baseComm, 
            cast(int) incomingEdges.length, cast(int*) incomingEdges.ptr, getWeightsPointer(incomingEdgeWeights),
            cast(int) outgoingEdges.length, cast(int*) outgoingEdges.ptr, getWeightsPointer(outgoingEdgeWeights),
            info, reorderInt, &result);
        return result;
    }

    MPI_Comm createDistributedGraphFromAdjacenciesUnweighted(
        const(int)[] incomingEdges, const(int)[] outgoingEdges,
        MPI_Comm baseComm = MPI_COMM_WORLD, bool reorder = false, MPI_Info info = MPI_INFO_NULL)
    {
        MPI_Comm result;
        int reorderInt = cast(int) reorder;
        MPI_Dist_graph_create_adjacent(
            baseComm, 
            cast(int) incomingEdges.length, cast(int*) incomingEdges.ptr, cast(int*) MPI_UNWEIGHTED,
            cast(int) outgoingEdges.length, cast(int*) outgoingEdges.ptr, cast(int*) MPI_UNWEIGHTED,
            info, reorderInt, &result);
        return result;
    }

    MPI_Comm createDistributedGraphFromNeighborsUnweighted(
        const(int)[] outgoingEdges, int rank, MPI_Comm baseComm = MPI_COMM_WORLD, bool reorder = false, MPI_Info info = MPI_INFO_NULL)
    {
        MPI_Comm result;
        int reorderInt = cast(int) reorder;
        int degree = cast(int) outgoingEdges.length;
        MPI_Dist_graph_create(baseComm, 1, &rank, 
            &degree, cast(int*) outgoingEdges.ptr, 
            cast(int*) MPI_UNWEIGHTED, info, reorderInt, &result); 
        return result;
    }

    MPI_Comm createDistributedGraphFromNeighbors(
        const(int)[] outgoingEdges, const(int)[] outgoingWeights, int rank, MPI_Comm baseComm = MPI_COMM_WORLD, bool reorder = false, MPI_Info info = MPI_INFO_NULL)
    {
        MPI_Comm result;
        int reorderInt = cast(int) reorder;
        int degree = cast(int) outgoingEdges.length;
        MPI_Dist_graph_create(baseComm, 1, &rank, 
            &degree, cast(int*) outgoingEdges.ptr, 
            getWeightsPointer(outgoingWeights), info, reorderInt, &result); 
        return result;
    }
}

int getCartesianRank(MPI_Comm comm, const(int)[] coordinates)
{
    int result;
    MPI_Cart_rank(comm, cast(int*) coordinates.ptr, &result);
    return result;
}

int getCartesianCoordinates(MPI_Comm comm, int rank, int[] coordinates)
{
    return MPI_Cart_coords(comm, rank, cast(int) coordinates.length, coordinates.ptr);
}

struct OffsetRanksTuple
{
    int[2] arrayof;
    ref int sourceRank() return { return arrayof[0]; } 
    ref int destinationRank() return { return arrayof[1]; } 
}

OffsetRanksTuple getCartesianShift(MPI_Comm comm, int axisIndex, int offset)
{
    OffsetRanksTuple result;
    MPI_Cart_shift(comm, axisIndex, offset, &(result.sourceRank()), &(result.destinationRank()));
    return result;
} 

// MPI_Comm createGraph(const(int)[][] edges, bool reorder = false, MPI_Comm baseComm = MPI_COMM_WORLD)
// {
//     int[] indices = new int[](edges.length);
//     indices[0] = edges[0].length;
//     foreach (i; 1..indices.length)
//         indices[i] = indices[i - 1] + edges[i].length;
// }

// https://www.mpi-forum.org/docs/mpi-4.0/mpi40-report.pdf#page=686&zoom=180,44,261
enum AccessMode : int
{
    Create                  = 1,    // MPI_MODE_CREATE
    ReadOnly                = 2,    // MPI_MODE_RDONLY
    WriteOnly               = 4,    // MPI_MODE_WRONLY
    ReadWrite               = 8,    // MPI_MODE_RDWR
    DeleteOnClose           = 16,   // MPI_MODE_DELETE_ON_CLOSE
    UniqueOpen              = 32,   // MPI_MODE_UNIQUE_OPEN
    ErrorIfCreatingExistent = 64,   // MPI_MODE_EXCL
    Append                  = 128,  // MPI_MODE_APPEND
    SequentialAccessOnly    = 256,  // MPI_MODE_SEQUENTIAL
}

File!accessMode openFile(AccessMode accessMode)(const(char)* fileName, 
    MPI_Comm comm = MPI_COMM_WORLD, MPI_Info info = MPI_INFO_NULL)
{
    File!accessMode result;
    MPI_File_open(comm, cast(char*) fileName, accessMode, info, &(result.handle));
    assert(result.handle != MPI_FILE_NULL);
    return result;
}

GenericFile openFile(AccessMode accessMode, const(char)* fileName, 
    MPI_Comm comm = MPI_COMM_WORLD, MPI_Info info = MPI_INFO_NULL)
{
    GenericFile result;
    MPI_File_open(comm, cast(char*) fileName, accessMode, info, &(result.handle));
    assert(result.handle != MPI_FILE_NULL);
    return result;
}


// https://www.mpi-forum.org/docs/mpi-4.0/mpi40-report.pdf#page=697&zoom=180,44,499
int setViewRaw(File, ReceiveDatatype)(ref File file, ReceiveDatatype receiveDatatype,
    size_t displacementBytes, MPI_Info info = MPI_INFO_NULL)
{
    // The symbol is either already aliased to MPI_Datatype, or has an alias this
    // to a datatype. 
    // TODO: this should probably not assume what this is and be more generic = a function call.
    MPI_Datatype etype = MPI_BYTE;
    MPI_Datatype ftype = receiveDatatype;
    assert(etype != INVALID_DATATYPE, "Provided elementary type was invalid");
    assert(ftype != INVALID_DATATYPE, "Provided target filetype was invalid");

    return MPI_File_set_view(file.handle, displacementBytes, etype, ftype, cast(char*) "native", info);
}

private mixin template BasicFile()
{
    MPI_File handle;

    void sync()
    {
        MPI_File_sync(handle);
    }

    int close()
    {
        return MPI_File_close(&handle);
    }
}

private mixin template WriteFile()
{
    void writeAt(Buffer)(Buffer buffer, MPI_Offset offset, MPI_Status* status = MPI_STATUS_IGNORE)
    {
        MPI_File_write_at(handle, offset, UnrollBuffer!buffer, status);
    }

    void write(Buffer)(Buffer buffer, MPI_Status* status = MPI_STATUS_IGNORE)
    {
        MPI_File_write(handle, UnrollBuffer!buffer, status);
    }
}

private mixin template ReadFile()
{
    void readAt(Buffer)(Buffer buffer, MPI_Offset offset, MPI_Status* status = MPI_STATUS_IGNORE)
    {
        MPI_File_read_at(handle, offset, UnrollBuffer!buffer, status);
    }

    void read(Buffer)(Buffer buffer, MPI_Status* status = MPI_STATUS_IGNORE)
    {
        MPI_File_read(handle, UnrollBuffer!buffer, status);
    }
}

private mixin template NonSequentialFile()
{
    void setSize(MPI_Offset size)
    {
        MPI_File_set_size(handle, size);
    }

    void preallocate(MPI_Offset size)
    {
        MPI_File_preallocate(handle, size);
    }

    MPI_Offset size()
    {
        MPI_Offset result;
        MPI_File_get_size(handle, &result);
        return result;
    }
}

// int deleteFile(AccessMode mode, File!mode* file)
// {
//     return MPI_File_delete(
// }

struct File(AccessMode mode)
{
    enum validationString = getValidationStringForAccessMode(mode);
    static assert(!validationString, validationString);

    mixin BasicFile!();
    static if(!(mode & AccessMode.SequentialAccessOnly))
        mixin NonSequentialFile!();
    static if (mode & (AccessMode.WriteOnly | AccessMode.ReadWrite))
        mixin WriteFile!();
    static if (mode & (AccessMode.ReadOnly | AccessMode.ReadWrite))
        mixin ReadFile!();
}

struct GenericFile
{
    mixin BasicFile!();
    mixin NonSequentialFile!();
    mixin WriteFile!();    
    mixin ReadFile!();    
}

private mixin template WriteFileView()
{
    void writeAt(Buffer)(Buffer buffer, MPI_Offset offset, MPI_Status* status = MPI_STATUS_IGNORE)
    {
        static assert(is(BufferInfo!buffer.ElementType == TElementary));
        file.writeAt(buffer, offset, status);
    }

    void write(Buffer)(Buffer buffer, MPI_Status* status = MPI_STATUS_IGNORE)
    {
        static assert(is(BufferInfo!buffer.ElementType == TElementary));
        file.write(buffer, status);
    }
}

private mixin template ReadFileView()
{
    void readAt(Buffer)(Buffer buffer, MPI_Offset offset, MPI_Status* status = MPI_STATUS_IGNORE)
    {
        static assert(is(BufferInfo!buffer.ElementType == TElementary));
        file.readAt(buffer, offset, status);
    }

    void read(Buffer)(Buffer buffer, MPI_Status* status = MPI_STATUS_IGNORE)
    {
        assert(is(BufferInfo!buffer.ElementType == TElementary));
        file.read(buffer, status);
    }
}

private mixin template NonSequentialFileView()
{
    void preallocate(size_t length) { file.preallocate(TElementary.sizeof * length); }
    void setSize(size_t length) { file.setSize(TElementary.sizeof * length); }
    size_t length() { return file.size / TElementary.sizeof; }
}



struct FileView(TFile, TElementary) 
{
    TFile* file;

    /// Sets the given view.
    int bind(ReceiveDatatype)(ReceiveDatatype receiveDatatype, 
        size_t displacementIndex, MPI_Info info = MPI_INFO_NULL)
    {
        MPI_Datatype etype = getDatatypeId!TElementary();
        MPI_Datatype ftype = receiveDatatype;
        assert(ftype != INVALID_DATATYPE, "Provided target filetype was invalid");

        return MPI_File_set_view(file.handle, displacementIndex * TElementary.sizeof, 
            etype, ftype, cast(char*) "native", info);
    }

    /// ditto
    int bind(size_t displacementIndex, MPI_Info info = MPI_INFO_NULL)
    {
        MPI_Datatype etype = getDatatypeId!TElementary();
        MPI_Datatype ftype = etype;
        assert(ftype != INVALID_DATATYPE, "Provided target filetype was invalid");

        return MPI_File_set_view(file.handle, cast(MPI_Offset) displacementIndex * TElementary.sizeof, 
            etype, ftype, cast(char*) "native", info);         
    }

    void sync() { file.sync(); }

    static if(is(TFile == GenericFile))
    {
        mixin WriteFileView!();
        mixin ReadFileView!();
        mixin NonSequentialFileView!();
    }

    else static if (is(TFile : File!mode, AccessMode mode))
    {
        static if (!(mode & AccessMode.SequentialAccessOnly))
            mixin NonSequentialFileView!();
        static if (mode & (AccessMode.WriteOnly | AccessMode.ReadWrite))
            mixin WriteFileView!();
        static if (mode & (AccessMode.ReadOnly | AccessMode.ReadWrite))
            mixin ReadFileView!();
    }
}


template createView(TElementary)
{
    auto createView(TFile)(ref TFile file)
    {
        return FileView!(TFile, TElementary)(&file);
    }
}

// {
//     auto createView(TElementary, TFile : File!mode, AccessMode mode)(ref TFile file)
//     {
//         return FileView!(TFile, TElementary)(file);
//     }

//     /// A nice helper
//     auto createView(TElementary, TFile : File!mode, AccessMode mode)(ref TFile file, size_t displacementIndex)
//     {
//         auto result = FileView!(TFile, TElementary)(file);
//         result.bind(Datatype!TElementary, displacementIndex);
//         return result;
//     }
// }

string getValidationStringForAccessMode(AccessMode mode)
{
    import std.conv : to;
    
    // https://www.mpi-forum.org/docs/mpi-4.0/mpi40-report.pdf#page=687&zoom=180,44,597
    if (mode & AccessMode.ReadOnly)
    {
        if (mode & AccessMode.Create)
            return "ReadOnly cannot be used in conjunction with Create";
        if (mode & AccessMode.ErrorIfCreatingExistent)
            return "ReadOnly cannot be used in conjunction with ErrorIfCreatingExistent";
    }

    bool areSet(AccessMode sourceFlags, AccessMode checkFlags) 
    { 
        return (sourceFlags & checkFlags) == checkFlags;
    }

    if (areSet(mode, AccessMode.ReadWrite | AccessMode.SequentialAccessOnly))
        return "ReadWrite cannot be used in conjunction with SequentialAccessOnly";

    AccessMode[] extractedFlags;
    foreach (flag; [AccessMode.ReadOnly, AccessMode.WriteOnly, AccessMode.ReadWrite])
    {
        if (mode & flag)
            extractedFlags ~= flag;
    }
    size_t foundCount = extractedFlags.length;
    if (foundCount == 0)
        return "You must specify exactly one of the following: ReadOnly, WriteOnly, ReadWrite";
    if (foundCount > 1)
    {
        string result = "The following are mutually exclusive: ReadOnly, WriteOnly, ReadWrite. You have specified ";
        result ~= to!string(foundCount);
        result ~= " of them: ";

        size_t commasLeft = foundCount - 1;
        foreach (flag; extractedFlags)
        {
            result ~= to!string(flag);
            if (commasLeft-- > 0)
                result ~= ",";
        }
        return result;
    }

    return null;
}

struct DynamicDatatype
{
    MPI_Datatype id;
    alias id this;
    int elementCount;

    /// Represents extent + lower bound.
    size_t diameter;
}

struct TypedDynamicDatatype(_ElementType)
{
    DynamicDatatype info;
    alias info this;
}

auto createDynamicArrayDatatype(Buffer)(Buffer targetBuffer)
    if (__traits(compiles, BufferInfo!targetBuffer))
{
    alias info = BufferInfo!targetBuffer;
    return createDynamicArrayDatatype!(info.ElementType)(cast(int) info.length);
}

TDatatype createDynamicArrayDatatype(TDatatype : DynamicDatatype)
    (TDatatype datatype, int elementCount)
    // if (is(TDatatype : DynamicDatatype))
{
    TDatatype result;
    result.elementCount = elementCount * datatype.elementCount;
    result.diameter = elementCount * datatype.diameter;

    MPI_Type_contiguous(cast(int) elementCount, datatype.id, &(result.id));
    MPI_Type_commit(&(result.id));
    return result;
}

TypedDynamicDatatype!ElementType createDynamicArrayDatatype(ElementType)(int elementCount)
    if (IsValidDatatype!ElementType)
{

    TypedDynamicDatatype!ElementType result;
    result.elementCount = elementCount;
    result.diameter = elementCount;
    
    MPI_Type_contiguous(cast(int) elementCount, getDatatypeId!ElementType, &(result.id));
    MPI_Type_commit(&(result.id));
    return result;
}

TypedDynamicDatatype!ElementType createVectorDatatype(ElementType)(
    int blockLength, int blockCount, int stride)
    if (IsValidDatatype!ElementType)
{
    
    TypedDynamicDatatype!ElementType result;
    result.elementCount = blockLength * blockCount;
    result.diameter = stride * blockCount;

    MPI_Type_vector(
        cast(int) blockCount, cast(int) blockLength, cast(int) stride, 
        getDatatypeId!ElementType, &(result.id));
    MPI_Type_commit(&(result.id));
    return result;
}


TDatatype createVectorDatatype(TDatatype : DynamicDatatype)(TDatatype datatype, 
    int blockLength, int blockCount, int stride)
{
    TDatatype result;
    result.elementCount = datatype.elementCount * blockLength * blockCount;
    result.diameter = datatype.diameter * stride * blockCount - datatype.diameter * blockLength;

    MPI_Type_vector(
        cast(int) blockCount, cast(int) blockLength, cast(int) stride, 
        datatype.id, &(result.id));
    MPI_Type_commit(&(result.id));

    return result;
}

// TDatatype createVectorDatatype(ElementType)(
//     int blockLength, int blockCount, int stride)
// {
//     static assert(IsValidDatatype!ElementType);
    
//     TypedDynamicDatatype!ElementType result;
//     result.elementCount = blockLength * blockCount;
//     result.diameter = stride * blockCount;

//     MPI_Type_vector(
//         cast(int) blockCount, cast(int) blockLength, cast(int) stride, 
//         getDatatypeId!ElementType, &(result.id));
//     MPI_Type_commit(&(result.id));
//     return result;
// }


TDatatype resizeDatatype(TDatatype : TypedDynamicDatatype!ElementType, ElementType)(
    TDatatype datatype, size_t desiredDiameter)
{
    TDatatype result;
    result.diameter = desiredDiameter;
    result.elementCount = datatype.elementCount;

    MPI_Aint extent, lb;
    MPI_Type_get_extent(datatype.id, &lb, &extent);
    
    MPI_Aint resultLb = lb;
    MPI_Aint resultExtent = (desiredDiameter * ElementType.sizeof) - lb;

    MPI_Type_create_resized(datatype.id, resultLb, resultExtent, &(result.id));
    return result;
}

// auto createStructDatatype(TDatatypeArray : TDatatype[N], TDatatype, size_t N)(
//     auto ref const TDatatypeArray datatypes, 
//     auto ref const MPI_Aint[N] displacements,
//     auto ref const int[N] blockLengths = 1)
// {
//     TDatatype result;
//     import std.algorithm, std.range;
//     result.elementCount = datatypes
//         .map!`a.elementCount`
//         .zip(blockLengths)
//         .fold!((accum, elementCount, count) => accum * elementCount * count)(1)
//         .staticArray;
    
//     MPI_Datatype[N] datatypeIds = datatypes.map!`a.id`.staticArray;
    
//     MPI_Type_create_struct(cast(int) N, 
//         blockLengths.ptr, displacements.ptr, datatypeIds.ptr, &(result.id));
//     MPI_Type_commit(&(result.id));

//     MPI_Aint lb;
//     MPI_Type_get_diameter(result.id, &lb, &(result.diameter));
//     result.diameter += lb;

//     return result;
// }

MPI_Datatype createStructDatatypeRaw(MPI_Datatype[] datatypeIds, MPI_Aint[] displacements, int[] blockLengths)
{
    assert(datatypeIds.length == displacements.length 
        && displacements.length == blockLengths.length);

    import std.algorithm : isStrictlyMonotonic;
    // Probably should check for overlapping? At least that of blockLengths?
    assert(isStrictlyMonotonic(displacements));

    MPI_Datatype result;
    MPI_Type_create_struct(cast(int) blockLengths.length, 
        blockLengths.ptr, displacements.ptr, datatypeIds.ptr, &result);
    MPI_Type_commit(&result);
    return result;
}

auto createStructDatatype(TDatatype, size_t N)(
    TDatatype*[N] datatypes, 
    MPI_Aint[N] displacements)
{
    int[N] blockLengths = 1;
    return createStructDatatype(datatypes, displacements, blockLengths);
}


auto createStructDatatype(TDatatype, size_t N)(
    TDatatype*[N] datatypes, 
    MPI_Aint[N] displacements, 
    int[N] blockLengths)
{
    TDatatype result;
    import std.algorithm, std.range;
    result.elementCount = datatypes[]
        .zip(blockLengths[])
        .fold!((a, tup) => a + tup[0].elementCount * tup[1])(0);
    
    MPI_Datatype[N] datatypeIds = void;
    foreach (i; 0..N) 
        datatypeIds[i] = datatypes[i].id;

    {static if (is(TDatatype : TypedDynamicDatatype!ElementType, ElementType))
    {
        displacements[] *= ElementType.sizeof;
    }}
    
    result.id = createStructDatatypeRaw(datatypeIds[], displacements[], blockLengths[]);

    MPI_Aint lb;
    MPI_Type_get_extent(result.id, &lb, cast(MPI_Aint*) &(result.diameter));
    result.diameter += lb;

    {static if (is(TDatatype : TypedDynamicDatatype!ElementType, ElementType))
    {
        result.diameter /= ElementType.sizeof;
    }}

    return result;
}

// MPI_Datatype createIndexedDatatypeRaw(MPI_Datatype elementType, int[] diplacements, int[] blockLengths)
// {
//     import std.algorithm : isStrictlyMonotonic;
//     assert(isStrictlyMonotonic(diplacements));

//     MPI_Type_create_indexed_block(diplacements.length, 
// }

// TypedDynamicDatatype!ElementType createIndexedDatatype(ElementType)(int[] displacements, int[] blockLengths)
// {
//     TypedDynamicDatatype!ElementType result;
//     import std.algorithm : sum, isStrictlyMonotonic;
//     result.elementCount = sum(blockLengths);
//     result.diameter = displacements[$ - 1] - displacements[0]
// }


/// Generates a random number and broadcasts it to all processes.
T bcastUniform(T)(T lowerBound, T upperBound, MPI_Comm comm = MPI_COMM_WORLD)
{
    T num;
    int myrank;
    MPI_Comm_rank(comm, &myrank);
    if (myrank == 0)
    {
        import std.random : uniform;
        num = uniform!T % (upperBound - lowerBound) + lowerBound;
    }
    bcast(&num, 0, comm);
    return num;
}



struct CyclicWorkLayoutInfo(size_t NUM_DIMS)
{
    int[NUM_DIMS] lastBlockSizes;
    int[NUM_DIMS] wholeBlockCountsPerProcess;
    int[NUM_DIMS] blockIndicesOfLastProcess;
    int blockSize;

    int getLastBlockSizeAtDimension(size_t dimIndex, int coord)
    {
        // Check if the last block is ours
        // Say there are 10 blocks and 4 processes:
        // [][][][][][][][][][]  ()()()()
        // Every process gets 2 blocks each, 2 more blocks remain:
        // [][] ()()()()
        // So if we subtract 10 - 8 we get 2, 
        // and the second process gets the last block.
        // The other processes that are to the right of it essentially get one less block.
        int index = blockIndicesOfLastProcess[dimIndex];
        if (coord < index)
        {
            return blockSize;
        }
        if (coord == index)
        {
            return lastBlockSizes[dimIndex];
        }
        return 0;
    }

    int getWorkSizeAtDimension(size_t dimIndex, int coord)
    {
        int dimWorkSize = wholeBlockCountsPerProcess[dimIndex] * blockSize;
        return getLastBlockSizeAtDimension(dimIndex, coord) + dimWorkSize;
    }

    int getWorkSizeForProcessAt(int[NUM_DIMS] coords)
    {
        int workSize = 1;
        foreach (dimIndex, coord; coords)
            workSize *= getWorkSizeAtDimension(dimIndex, coord);
        return workSize;
    }
}

/// Returns the data layout description of an N-dimensional matrix of the given `matrixDimensions` size,
/// per `computeGridDimensions` processes, each process getting `blockSize` blocks.
/// The algorithm is called "cyclic block distribution".
/// Refer to e.g. the link below (I did not study by that link, the implementation is trivial as it stands):
/// https://link.springer.com/content/pdf/10.1007%2F3-540-61626-8_20.pdf
auto getCyclicLayoutInfo(TArray : int[N], size_t N)(
    TArray matrixDimensions, TArray computeGridDimensions, int blockSize)
{
    CyclicWorkLayoutInfo!N result;
    // Ceiling. Includes the last block.
    int[N] blockCounts = (matrixDimensions[] + blockSize - 1) / blockSize;
    // Last column or row may be incomplete
    result.lastBlockSizes[]             = matrixDimensions[] - (blockCounts[] - 1) * blockSize;
    result.wholeBlockCountsPerProcess[] = matrixDimensions[] / (blockSize * computeGridDimensions[]);
    result.blockIndicesOfLastProcess[]  = blockCounts[] - result.wholeBlockCountsPerProcess[] * computeGridDimensions[] - 1;
    result.blockSize = blockSize;
    return result;
}

void printAsMatrix(int[] data, int width)
{
    import std.stdio : writef, writeln;
    import std.range : iota;
    
    foreach (rowStartIndex; iota(0, data.length, width))
    {
        foreach (i; 0..width)
            writef("%3d", data[rowStartIndex + i]);
        writeln();
    }
}
    
// struct WriteCommInfo
// {
//     MPI_Group groupHandle;
//     MPI_Comm commHandle;
//     mh.GroupInfo groupInfo;
//     alias info this;
// }