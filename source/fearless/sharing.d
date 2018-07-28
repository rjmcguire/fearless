/**
   D implementation of Rust's std::sync::Mutex
*/
module fearless.sharing;

import fearless.from;

/**
   A new exclusive reference to a payload of type T constructed from args.
   Allocated on the GC to make sure its lifetime is infinite and therefore
   safe to pass to other threads.
 */
auto gcExclusive(T, A...)(auto ref A args) {
    return new shared ExclusiveImpl!T(args);
}

/**
   A new exclusive reference to a payload.
   Allocated on the GC to make sure its lifetime is infinite and therefore
   safe to pass to other threads.

   This function sets the passed-in payload to payload.init to make sure
   that no references to it can be unsafely used.
 */
auto gcExclusive(T)(ref T payload) if(!from!"std.traits".hasUnsharedAliasing!T) {
    return new shared ExclusiveImpl!T(payload);
}

version(none) version(Have_automem) {
    /**
       A reference counted exclusive object (see above).
    */
    auto rcExclusive(T, A...)(auto ref A args) {
        import automem.ref_counted: RefCounted;
        return RefCounted!(ExclusiveImpl!T)(args);
    }
}


alias Exclusive(T) = shared(ExclusiveImpl!T);


/**
   Provides @safe exclusive access (via a mutex) to a payload of type T.
   Allows to share mutable data across threads safely.
 */
package struct ExclusiveImpl(T) {

    // TODO: make the mutex type a parameter
    import core.sync.mutex: Mutex;

    private T _payload;
    private Mutex _mutex;
    private bool _locked;

    @disable this(this);

    /**
       The constructor is responsible for initialising the payload so that
       it's not possible to escape it.
     */
    private this(A...)(auto ref A args) shared {
        import std.functional: forward;
        this._payload = T(forward!args);
        init();
    }

    private this(ref T payload) shared {
        import std.algorithm: move;
        import std.traits: Unqual;

        _payload = () @trusted {  return cast(shared) move(payload); }();
        payload = payload.init;

        init();
    }

    private void init() shared {
        this._mutex = new shared Mutex;
    }

    bool isLocked() shared const {
        return _locked;
    }

    /**
       Obtain exclusive access to the payload. The mutex is locked and
       when the returned `Guard` object's lifetime is over the mutex
       is unloked.
     */
    auto lock() shared {
        () @trusted { _mutex.lock_nothrow; }();
        _locked = true;
        return Guard(&_payload, _mutex, &_locked);
    }

    // non-static didn't work - weird error messages
    static struct Guard {

        private shared T* _payload;
        private shared Mutex _mutex;
        private shared bool* _locked;

        alias reference this;

        scope ref T reference() @trusted return {
            return *(cast(T*) _payload);
        }

        ~this() scope @trusted {
            _mutex.unlock_nothrow();
            *_locked = false;
        }
    }
}
