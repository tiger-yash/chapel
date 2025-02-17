/*
 * Copyright 2020-2021 Hewlett Packard Enterprise Development LP
 * Copyright 2004-2019 Cray Inc.
 * Other additional copyright holders may be indicated within.
 *
 * The entirety of this work is licensed under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 *
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// NOTE: the docs below are intended to be included
// in the relevant spec section

/*

 */
module ChapelLocale {

  public use LocaleModel;
  import HaltWrappers;
  use SysCTypes, CPtr;

  compilerAssert(!(!localeModelHasSublocales &&
   localeModelPartitionsIterationOnSublocales),
   "Locale model without sublocales can not have " +
   "localeModelPartitionsIterationOnSublocales set to true.");

  //
  // Node and sublocale types and special sublocale values.
  //
  pragma "no doc"
  type chpl_nodeID_t = int(32);
  pragma "no doc"
  type chpl_sublocID_t = int(32);

  pragma "no doc"
  extern const c_sublocid_none: chpl_sublocID_t;
  pragma "no doc"
  extern const c_sublocid_any: chpl_sublocID_t;
  pragma "no doc"
  extern const c_sublocid_all: chpl_sublocID_t;

  pragma "no doc"
  inline proc chpl_isActualSublocID(subloc: chpl_sublocID_t)
    return (subloc != c_sublocid_none
            && subloc != c_sublocid_any
            && subloc != c_sublocid_all);
  
  /*
    regular: Has a concrete BaseLocale instance
    any: Placeholder to represent the notion of "anywhere"
    nilLocale: The _instance is set to nil. Used during setup. Also, as a
               sentinel value in locale tree operations
    dummy: Used during initialization for `here` before it is properly setup
    default: Used to store the default locale instance. Initially set to nil,
             then "fixed" by LocalesArray to Locales[0]
   */
  pragma "no doc"
  enum localeKind { regular, any, nilLocale, dummy, default };

  pragma "locale private"
  pragma "no doc"
  const nilLocale = new locale(localeKind.nilLocale);
  pragma "locale private"
  pragma "no doc"
  var defaultLocale = new locale(localeKind.default);

  // dummyLocale is not locale private. We use it before locales initialized in
  // the first place, so it should stay in the locale that started the
  // execution.
  pragma "no doc"
  var dummyLocale = new locale(localeKind.dummy);

  // record locale - defines the locale record - called _locale to aid parsing
  pragma "no doc"
  pragma "always RVF"
  record _locale {

    var _instance: unmanaged BaseLocale?;

    inline proc _value {
      return _instance!;
    }

    forwarding _value;

    // default initializer for the locale record.
    proc init() {
      if rootLocaleInitialized {
        this._instance = defaultLocale._instance;
      }
      else {
        /*this._instance = new unmanaged LocaleModel();*/
        this._instance = nil;
      }
    }

    // used internally during setup
    proc init(_instance: BaseLocale) {
      this._instance = _to_unmanaged(_instance);
    }

    proc init(param kind) {
      if kind == localeKind.regular then
        compilerError("locale.init(kind) can not be used to create ",
                      "a regular locale instance");
      else if kind == localeKind.dummy then
        this._instance = new unmanaged DummyLocale();
      else if kind == localeKind.default then
        this._instance = nil;
    }

    proc init=(other: locale) {
      this._instance = other._instance;
    }

    proc deinit() { }

    // the following are normally taken care of by `forwarding`. However, they
    // don't work if they are called in a promoted expression. See 15148

    inline proc localeid {
      return this._value.localeid;
    }

    inline proc chpl_id() {
      return this._value.chpl_id();
    }

    inline proc chpl_localeid() {
      return this._value.chpl_localeid();
    }

    inline proc chpl_name() {
      return this._value.chpl_name();
    }

    inline proc defaultMemory() {
      return this._value.defaultMemory();
    }

    inline proc largeMemory() {
      return this._value.largeMemory();
    }

    inline proc lowLatencyMemory() {
      return this._value.lowLatencyMemory();
    }

    inline proc highBandwidthMemory() {
      return this._value.highBandwidthMemory();
    }

    inline proc getChildCount() {
      return this._value.getChildCount();
    }

  } // end of record _locale


  /*
    This returns the locale from which the call is made.

    :return: current locale
    :rtype: locale
  */
  pragma "no doc" // because the spec covers it in a different section
  inline proc here {
    return chpl_localeID_to_locale(here_id);
  }

  // Locale methods we want to have show up in chpldoc start here:

  /*
    Get the hostname of this locale.

    :returns: the hostname of the compute node associated with the locale
    :rtype: string
  */
  inline proc locale.hostname {
    return this._value.hostname;
  }

  /*
    Get the name of this locale.  In practice, this is often the
    same as the hostname, though in some cases (like when using
    local launchers), it may be modified.

    :returns: locale name
    :rtype: string
  */
  inline proc locale.name {
    return this._value.name;
  }

  /*
    Get the unique integer identifier for this locale.

    :returns: locale number, in the range ``0..numLocales-1``
    :rtype: int
  */
  inline proc locale.id {
    return this._value.id;
  }

  /*
    This is the maximum task concurrency that one can expect to
    achieve on this locale.  The value is an estimate by the
    runtime tasking layer.  Typically it is the number of physical
    processor cores available to the program.  Creating more tasks
    than this will probably increase walltime rather than decrease
    it.
  */
  inline proc locale.maxTaskPar { return this._value.maxTaskPar; }

  // the following are normally taken care of by `forwarding`. However, they
  // don't work if they are called in a promoted expression. See 15148

  /*
    A *processing unit* or *PU* is an instance of the processor
    architecture, basically the thing that executes instructions.
    :proc:`locale.numPUs` tells how many of these are present on this
    locale.  It can count either physical PUs (commonly known as
    *cores*) or hardware threads such as hyperthreads and the like.
    It can also either take into account any OS limits on which PUs
    the program has access to or do its best to ignore such limits.
    By default it returns the number of accessible physical cores.

    :arg logical: Count logical PUs (hyperthreads and the like),
                  or physical ones (cores)?  Defaults to `false`,
                  for cores.
    :type logical: `bool`
    :arg accessible: Count only PUs that can be reached, or all of
                     them?  Defaults to `true`, for accessible PUs.
    :type accessible: `bool`
    :returns: number of PUs
    :rtype: `int`

    There are several things that can cause the OS to limit the
    processor resources available to a Chapel program.  On plain
    Linux systems using the ``taskset(1)`` command will do it.  On
    Cray systems the ``CHPL_LAUNCHER_CORES_PER_LOCALE`` environment
    variable may do it, indirectly via the system job launcher.
    Also on Cray systems, using a system job launcher (``aprun`` or
    ``slurm``) to run a Chapel program manually may do it, as can
    running programs within Cray batch jobs that have been set up
    with limited processor resources.
  */
  inline proc locale.numPUs(logical: bool = false, accessible: bool = true) {
    return this._value.numPUs(logical, accessible);
  }

  /*
    ``callStackSize`` holds the size of a task stack on a given
    locale.  Thus, ``here.callStackSize`` is the size of the call
    stack for any task on the current locale, including the
    caller.
  */
  inline proc locale.callStackSize { return this._value.callStackSize; }

  /*
    :returns: the number of tasks that have begun executing, but have not yet finished
    :rtype: `int`

    Note that this number can exceed the number of non-idle threads
    because there are cases in which a thread is working on more than
    one task. As one example, in fifo tasking, when a parent task
    creates child tasks to execute the iterations of a coforall
    construct, the thread the parent is running on may temporarily
    suspend executing the parent task in order to help with the child
    tasks, until the construct completes. When this occurs the count
    of running tasks can include both the parent task and a child,
    although strictly speaking only the child is executing
    instructions.

    As another example, any tasking implementation in which threads
    can switch from running one task to running another, such as
    qthreads, can have more tasks running than threads on which to run
    them.
  */
  pragma "fn synchronization free"
  proc locale.runningTasks() {
    return this.runningTaskCnt();
  }

  pragma "no doc"
  operator locale.=(ref l1: locale, const ref l2: locale) {
    l1._instance = l2._instance;
  }

  /*
    ``locale`` is the abstract class from which the various
    implementations inherit.  It specifies the required interface
    and implements part of it, but requires the rest to be provided
    by the corresponding concrete classes.
   */
  pragma "no doc"
  class BaseLocale {
    //- Constructor
    pragma "no doc"
    proc init() { }

    pragma "no doc"
    proc init(parent: locale) {
      this.parent = parent;
    }

    //------------------------------------------------------------------------{
    //- Fields and accessors defined for all locale types (not overridable)
    //-

    // Every locale has a parent, except for the root locale.
    // The parent of the root locale is nil (by definition).
    pragma "no doc"
    const parent = nilLocale;

    pragma "no doc" var nPUsLogAcc: int;     // HW threads, accessible
    pragma "no doc" var nPUsLogAll: int;     // HW threads, all
    pragma "no doc" var nPUsPhysAcc: int;    // HW cores, accessible
    pragma "no doc" var nPUsPhysAll: int;    // HW cores, all

    inline
    proc numPUs(logical: bool = false, accessible: bool = true)
      return if logical
             then if accessible then nPUsLogAcc else nPUsLogAll
             else if accessible then nPUsPhysAcc else nPUsPhysAll;

    var maxTaskPar: int;

    var callStackSize: size_t;

    proc id : int return chpl_nodeFromLocaleID(__primitive("_wide_get_locale", this));

    pragma "no doc"
    proc localeid : chpl_localeID_t return __primitive("_wide_get_locale", this);

    proc hostname: string {
      extern proc chpl_nodeName(): c_string;
      var hname: string;
      on this {
        try! {
          hname = createStringWithNewBuffer(chpl_nodeName());
        }
      }
      return hname;
    }

    override proc writeThis(f) throws {
      HaltWrappers.pureVirtualMethodHalt();
    }

    proc name return chpl_name() : string;

    // This many tasks are running on this locale.
    //
    // Note handling runningTaskCounter <= 0 in runningTaskCnt().  The
    // references to it are done via here.runningTasks(), and currently
    // "here" means the requested locale, not the actual or concrete
    // one.  But this may be "any", and the running task count in it may
    // be zero, which in turn leads to overindexing the locales array
    // after the subtraction of 1 in locale.runningTasks(), below.  In
    // the long run we probably need to go through all the "here" refs
    // in the module code and differentiate more carefully which need
    // the requested locale and which need the concrete one.  But for
    // now, we make the assumption that all requests for the number of
    // running tasks want the count from the locale the calling task is
    // running on, so the minimum possible value must be 1.
    //
    // This field should only be accessed locally, so we will have better
    // performance if we always use a processor atomic.
    pragma "no doc"
    var runningTaskCounter : chpl__processorAtomicType(int);

    pragma "no doc"
    inline proc runningTaskCntSet(val : int) {
      runningTaskCounter.write(val, memoryOrder.relaxed);
    }

    pragma "no doc"
    inline proc runningTaskCntAdd(val : int) {
      runningTaskCounter.add(val, memoryOrder.relaxed);
    }

    pragma "no doc"
    inline proc runningTaskCntSub(val : int) {
      runningTaskCounter.sub(val, memoryOrder.relaxed);
    }

    pragma "no doc"
    inline proc runningTaskCnt() {
      var rtc = runningTaskCounter.read(memoryOrder.relaxed);
      return if (rtc <= 0) then 1 else rtc;
    }
    //------------------------------------------------------------------------}

    //------------------------------------------------------------------------{
    //- User Interface Methods (overridable)
    //-

    // These are dynamically dispatched, so they can be overridden in
    // concrete classes.
    pragma "no doc"
    proc chpl_id() : int {
      HaltWrappers.pureVirtualMethodHalt();
      return -1;
    }

    pragma "no doc"
    proc chpl_localeid() : chpl_localeID_t {
      HaltWrappers.pureVirtualMethodHalt();
      return chpl_buildLocaleID(-1:chpl_nodeID_t, c_sublocid_none);
    }

    pragma "no doc"
    proc chpl_name() : string {
      HaltWrappers.pureVirtualMethodHalt();
      return "";
    }

    //
    // Support for different types of memory:
    // large, low latency, and high bandwidth
    //
    pragma "no doc"
    proc defaultMemory() : locale {
      HaltWrappers.pureVirtualMethodHalt();
    }

    pragma "no doc"
    proc largeMemory() : locale {
      HaltWrappers.pureVirtualMethodHalt();
    }

    pragma "no doc"
    proc lowLatencyMemory() : locale {
      HaltWrappers.pureVirtualMethodHalt();
    }

    pragma "no doc"
    proc highBandwidthMemory() : locale {
      HaltWrappers.pureVirtualMethodHalt();
    }

    pragma "no doc"
    proc getChildCount() : int {
      HaltWrappers.pureVirtualMethodHalt();
      return 0;
    }
  
// Part of the required locale interface.
// Commented out because presently iterators are statically bound.
//    iter getChildIndices() : int {
//      for idx in this.getChildSpace do
//        yield idx;
//    }
  
    pragma "no doc"
    proc addChild(loc:locale)
    {
      HaltWrappers.pureVirtualMethodHalt();
    }
  
    pragma "no doc"
    proc getChild(idx:int) : locale {
      HaltWrappers.pureVirtualMethodHalt();
    }

// Part of the required locale interface.
// Commented out because presently iterators are statically bound.
//    iter getChildren() : locale  {
//    HaltWrappers.pureVirtualMethodHalt();
//      yield 0;
//    }

    //------------------------------------------------------------------------}
  }

  /* This class is used during initialization and is returned when
     'here' is used before the locale hierarchy is initialized.  This is due to
     the fact that "here" is used for memory and task control in setting up the
     architecture itself.  DummyLocale provides system-default tasking and
     memory management.
   */
  pragma "no doc"
  class DummyLocale : BaseLocale {
    proc init() { 
      super.init(nilLocale);
    }

    override proc chpl_id() : int {
      return -1;
    }
    override proc chpl_localeid() : chpl_localeID_t {
      return chpl_buildLocaleID(-1:chpl_nodeID_t, c_sublocid_none);
    }
    override proc chpl_name() : string {
      return "dummy-locale";
    }
    override proc getChildCount() : int {
      return 0;
    }
    override proc getChild(idx:int) : locale {
      return new locale(this);
    }
    override proc addChild(loc:locale)
    {
      halt("addChild on DummyLocale");
    }
  }


  // Returns a reference to a singleton array (stored in AbstractLocaleModel)
  // storing this locale.
  //
  // This singleton array is useful for some array/domain implementations
  // (such as DefaultRectangular) to help the targetLocales call return
  // by 'const ref' without requiring the array/domain implementation
  // to store another array.
  pragma "no doc"
  proc chpl_getSingletonLocaleArray(arg: locale) const ref
  lifetime return c_sublocid_none // indicate return has global lifetime
  {
    var casted = arg._instance:borrowed AbstractLocaleModel?;
    if casted == nil then
      halt("cannot call chpl_getSingletonCurrentLocaleArray on nil or rootLocale");

    return casted!.chpl_singletonThisLocaleArray;
  }

  pragma "no doc"
  class AbstractLocaleModel : BaseLocale {
    // Used in chpl_getSingletonLocaleArray -- see the comment there
    var chpl_singletonThisLocaleArray:[0..0] locale;

    // This will be used for interfaces that will be common to all
    // (non-RootLocale) locale models
    proc init(parent_loc : locale) {
      super.init(parent_loc);
    }

    proc init() {  }
  }

  // rootLocale is declared to be of type locale rather than
  // RootLocale because doing so would make locales depend on arrays
  // which depend on locales, etc.
  //
  // If we had a way to express domain and array return types abstractly,
  // that problem would go away. <hilde>
  //
  // The rootLocale is private to each locale.  It cannot be
  // initialized until LocaleModel is initialized.  To disable this
  // replication, set replicateRootLocale to false.
  pragma "no doc"
  pragma "locale private" var rootLocale = nilLocale;

  pragma "no doc"
  config param replicateRootLocale = true;

  // The rootLocale needs to be initialized on all locales prior to
  // initializing the Locales array.  Unfortunately, the rootLocale
  // cannot be properly replicated until DefaultRectangular can be
  // initialized (as the private copies of the defaultDist are
  // needed).  We remedy this by initializing a rootLocale on locale 0
  // (called origRootLocale), and setting all locales' rootLocale to
  // origRootLocale.  Later, after DefaultRectangular can be
  // initialized, we create local copies of the rootLocale (and the
  // Locales array).
  //
  pragma "no doc"
  var origRootLocale = nilLocale;

  pragma "no doc"
  class AbstractRootLocale : BaseLocale {
    proc init() { }

    proc init(parent_loc : locale) {
      super.init(parent_loc);
    }

    // These functions are used to establish values for Locales[] and
    // LocaleSpace -- an array of locales and its corresponding domain
    // which are used as the default set of targetLocales in many
    // distributions.
    proc getDefaultLocaleSpace() const ref {
      HaltWrappers.pureVirtualMethodHalt();
      return chpl_emptyLocaleSpace;
    }

    proc getDefaultLocaleArray() const ref {
      HaltWrappers.pureVirtualMethodHalt();
      return chpl_emptyLocales;
    }

    proc localeIDtoLocale(id : chpl_localeID_t) : locale {
      HaltWrappers.pureVirtualMethodHalt();
    }

    // These iterators are to be used by RootLocale:setup() to
    // initialize the LocaleModel.  The calling loop body cannot
    // contain any non-local code, since the rootLocale is not yet
    // initialized.
    iter chpl_initOnLocales() {
      if numLocales > 1 then
        halt("The locales must be initialized in parallel");
      for locIdx in (origRootLocale._instance:borrowed RootLocale?)!.getDefaultLocaleSpace() {
        yield locIdx;
        rootLocale = origRootLocale;
        rootLocaleInitialized = true;
      }
    }

    // Since we are going on to all the locales here, we use the
    // opportunity to initialize any global private variables we
    // either need (e.g., defaultDist) or can do at this point in
    // initialization (e.g., rootLocale).
    iter chpl_initOnLocales(param tag: iterKind)
      where tag==iterKind.standalone {
      // Simple locales barrier, see implementation below for notes
      var b: localesBarrier;
      var flags: [1..#numLocales-1] unmanaged localesSignal?;
      coforall locIdx in 0..#numLocales /*ref(b)*/ {
        on __primitive("chpl_on_locale_num",
                       chpl_buildLocaleID(locIdx:chpl_nodeID_t,
                                          c_sublocid_any)) {
          chpl_defaultDistInitPrivate();
          yield locIdx;
          b.wait(locIdx, flags);
          chpl_rootLocaleInitPrivate(locIdx);
          chpl_defaultLocaleInitPrivate();
          chpl_singletonCurrentLocaleInitPrivate(locIdx);
          warmupRuntime();
        }
      }
    }
  }

  // Warm up runtime components. For tasking layers that have a fixed number of
  // threads, we create a task on each thread to warm it up (e.g. grab some
  // initial call stacks.) We also warm up the memory layer, since allocators
  // tend to have per thread pools/arenas.
  private proc warmupRuntime() {
    extern proc chpl_task_getFixedNumThreads(): uint(32);
    coforall i in 0..#chpl_task_getFixedNumThreads() {
      var p = c_malloc(int, 1);
      p[0] = i;
      c_free(p);
    }
  }

  //
  // Simple locales barrier
  //
  // This sits outside of the abstract root locale definition above
  // because the compiler cannot resolve the constructor (known issues
  // with nested classes/records).  In addition, we cannot have the
  // flags array in the record, because the initCopy function needs
  // the dataPar* configs declared in ChapelDistribution.
  //
  // Each non-0 locale increments the count, and then waits on a
  // *local* atomic.  This is done by creating an array of type
  // class localesSignal, one per locale, and allocating each locale's
  // copy before updating the count.  Locale 0 waits for the others to
  // arrive and then set the signals to true.  We can't do anything
  // too complicated this early on, so we are using a for loop to
  // broadcast that we are done.
  pragma "no doc"
  class localesSignal {
    var s: atomic bool;

    // Override default initializer; this could go away when the
    // compiler's default initializer creates a version that takes a
    // bool rather than an 'atomic bool' (which generates a
    // '--warn-unstable' warning otherwise)
    proc init() {
    }
  }
  pragma "no doc"
  record localesBarrier {
    proc wait(locIdx, flags) {
      if locIdx==0 {
        // locale 0 has nothing else to do, so check flags
        while (true) {
          // This fence ensures that writes to the count variables
          // are available to this task. (Note that they aren't
          // atomic if they're 128-bit writes though - so we
          // have some risk of getting part of a wide pointer).
          // Without this fence, there is a race condition on
          // a weakly-ordered architecture.
          atomicFence();
          var count = 0;
          for f in flags do
            if f then count += 1;
          if count==numLocales-1 then break;
          // Give time to other tasks/threads/processes
          // like we do in waitFor
          chpl_task_yield();
        }
        // Let the others go
        for f in flags do
          f!.s.testAndSet();
      } else {
        var f = new unmanaged localesSignal();
        // expose my flag to locale 0
        flags[locIdx] = f;
        // wait (locally) for locale 0 to set my flag
        f.s.waitFor(true);
        // clean up
        delete f;
      }
    }
  }


  // This function is called in the LocaleArray module to initialize
  // the rootLocale.  It sets up the origRootLocale and also includes
  // set up of the each locale's LocaleModel via RootLocale:init().
  //
  // The init() function must use the chpl_initOnLocales() iterator above
  // to iterate in parallel over the locales to set up the LocaleModel
  // object.
  pragma "no doc"
  proc chpl_init_rootLocale() {
    if numLocales > 1 && _local then
      halt("Cannot run a program compiled with --local in more than 1 locale");

    origRootLocale._instance = new unmanaged RootLocale();
    (origRootLocale._instance:borrowed RootLocale?)!.setup();
  }

  // This function sets up a private copy of rootLocale by replicating
  // origRootLocale and resets the Locales array to point to the local
  // copy on all but locale 0 (which is done in LocalesArray.chpl as
  // part of the declaration).
  pragma "no doc"
  proc chpl_rootLocaleInitPrivate(locIdx) {
    // Even when not replicating the rootLocale, we must temporarily
    // set the rootLocale to the original version on locale 0, because
    // the initialization below needs to get/set locale ids.
    rootLocale = origRootLocale;
    if replicateRootLocale && locIdx!=0 {
      // Create a new local rootLocale
      var newRootLocale = new unmanaged RootLocale();
      // We don't want to be doing unnecessary ref count updates here
      // as they require additional tasks.  We know we don't need them
      // so tell the compiler to not insert them.
      pragma "no copy" pragma "no auto destroy"
      const ref origLocales = (origRootLocale._instance:borrowed RootLocale?)!.getDefaultLocaleArray();
      var origRL = origLocales._value.theData;
      var newRL = newRootLocale.getDefaultLocaleArray()._value.theData;
      // We must directly implement a bulk copy here, as the mechanisms
      // for doing so via a whole array assignment are not initialized
      // yet and copying element-by-element via a for loop is costly.
      __primitive("chpl_comm_array_get",
                  __primitive("array_get", newRL, 0),
                  0 /* locale 0 */,
                  __primitive("array_get", origRL, 0), 
                  numLocales:size_t);
      // Set the rootLocale to the local copy
      rootLocale._instance = newRootLocale;
    }
    if locIdx!=0 {
      // We mimic a private Locales array alias by using the move
      // primitive.
      pragma "no auto destroy"
      const ref tmp = (rootLocale._instance:borrowed RootLocale?)!.getDefaultLocaleArray();
      __primitive("move", Locales, tmp);
    }
    rootLocaleInitialized = true;
  }

  pragma "no doc"
  proc chpl_defaultLocaleInitPrivate() {
    pragma "no copy" pragma "no auto destroy"
    const ref rl = (rootLocale._instance:borrowed RootLocale?)!.getDefaultLocaleArray();
    defaultLocale._instance = rl[0]._instance;
  }

  pragma "no doc"
  proc chpl_singletonCurrentLocaleInitPrivateSublocs(arg: locale) {
    for i in 0..#arg.getChildCount() {
      var subloc = arg.getChild(i);

      var val = subloc._instance:unmanaged AbstractLocaleModel?;
      if val == nil then
        halt("error in locale initialization");

      val!.chpl_singletonThisLocaleArray[0]._instance = val;

      chpl_singletonCurrentLocaleInitPrivateSublocs(subloc);
    }
  }
  pragma "no doc"
  proc chpl_singletonCurrentLocaleInitPrivate(locIdx) {
    pragma "no copy" pragma "no auto destroy"
    const ref rl = (rootLocale._instance:borrowed RootLocale?)!.getDefaultLocaleArray();
    var loc = rl[locIdx];
    var val = loc._instance:unmanaged AbstractLocaleModel?;
    if val == nil then
      halt("error in locale initialization");

    val!.chpl_singletonThisLocaleArray[0]._instance = val;
    chpl_singletonCurrentLocaleInitPrivateSublocs(loc);
  }

  pragma "fn synchronization free"
  pragma "no doc"
  extern proc chpl_task_getRequestedSubloc(): chpl_sublocID_t;

  pragma "no doc"
  pragma "insert line file info"
  export
  proc chpl_getLocaleID(ref localeID: chpl_localeID_t) {
    localeID = here_id;
  }

  // Return the locale ID of the current locale
  pragma "no doc"
  inline proc here_id {
    if localeModelHasSublocales then
      return chpl_rt_buildLocaleID(chpl_nodeID, chpl_task_getRequestedSubloc());
    else
      return chpl_rt_buildLocaleID(chpl_nodeID, c_sublocid_any);
  }

  // Returns a wide pointer to the locale with the given id.
  pragma "no doc"
  pragma "fn returns infinite lifetime"
  proc chpl_localeID_to_locale(id : chpl_localeID_t) : locale {
    if rootLocale._instance != nil then
      return (rootLocale._instance:borrowed AbstractRootLocale?)!.localeIDtoLocale(id);
    else {
      // For code prior to rootLocale initialization
      // in cases where we capture functions as FCF, module initialization order
      // changes in a way that IO is inited too early. In that scenario, we
      // somehow don't get dummyLocale set up correctly in this scheme 
      // remove this check, and test/exits/albrecht/exitWithNoCall fails
      if dummyLocale._instance == nil {
        dummyLocale._instance = new unmanaged DummyLocale();
      }
      return dummyLocale;
    }
  }

//########################################################################{
//# Locale diagnostics
//#

  pragma "no doc"
  deprecated "locale.totalThreads() is deprecated; please let us know if this is a problem for you"
  proc locale.totalThreads() {
    var totalThreads: int;
    extern proc chpl_task_getNumThreads() : uint(32);
    on this do totalThreads = chpl_task_getNumThreads();
    return totalThreads;
  }
  
  pragma "no doc"
  deprecated "locale.idleThreads() is deprecated; please let us know if this is a problem for you"
  proc locale.idleThreads() {
    var idleThreads: int;
    extern proc chpl_task_getNumIdleThreads() : uint(32);
    on this do idleThreads = chpl_task_getNumIdleThreads();
    return idleThreads;
  }
  
  pragma "no doc"
  deprecated "locale.queuedTasks() is deprecated; please let us know if this is a problem for you"
  proc locale.queuedTasks() {
    var queuedTasks: int;
    extern proc chpl_task_getNumQueuedTasks() : uint(32);
    on this do queuedTasks = chpl_task_getNumQueuedTasks();
    return queuedTasks;
  }

  pragma "no doc"
  deprecated "locale.blockedTasks() is deprecated; please let us know if this is a problem for you"
  proc locale.blockedTasks() {
    var blockedTasks: int;
    extern proc chpl_task_getNumBlockedTasks() : int(32);
    on this do blockedTasks = chpl_task_getNumBlockedTasks();
    return blockedTasks;
  }

//########################################################################}

  //
  // Increment and decrement the task count.
  //
  // Elsewhere in the module code we adjust the running task count
  // directly, but at least for now the runtime also needs to be
  // able to do so.  These functions support that.
  //
  pragma "no doc"
  pragma "insert line file info"
  pragma "inc running task"
  export
  proc chpl_taskRunningCntInc() {
    if rootLocaleInitialized {
      here.runningTaskCntAdd(1);
    }
  }

  pragma "no doc"
  pragma "insert line file info"
  pragma "dec running task"
  export
  proc chpl_taskRunningCntDec() {
    if rootLocaleInitialized {
      here.runningTaskCntSub(1);
    }
  }

  pragma "no doc"
  pragma "insert line file info"
  export
  proc chpl_taskRunningCntReset() {
    here.runningTaskCntSet(0);
  }

  pragma "no doc"
  proc deinit() {
    delete origRootLocale._instance;
    delete dummyLocale._instance;
  }
}
