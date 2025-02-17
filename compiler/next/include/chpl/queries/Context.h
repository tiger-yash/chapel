/*
 * Copyright 2021 Hewlett Packard Enterprise Development LP
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

#ifndef CHPL_QUERIES_CONTEXT_H
#define CHPL_QUERIES_CONTEXT_H

#include "chpl/queries/Context-detail.h"
#include "chpl/queries/ID.h"
#include "chpl/queries/CommentID.h"
#include "chpl/queries/UniqueString.h"
#include "chpl/util/memory.h"
#include "chpl/util/hash.h"
#include "chpl/util/break.h"

#include <memory>
#include <tuple>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace chpl {

namespace uast {
  class ASTNode;
}

namespace resolution {
  class TypedFnSignature;
}


/**

\rst

This class stores the compilation-wide context. Another name for this
compilation-wide context is *program database*. It handles unique'd strings and
also stores the results of queries (so that they are are memoized). It tracks
dependencies of queries in order to update them appropriately when a dependency
changes.

Queries are functions that are written in a stylized manner to interact with the
context (aka program database). For example, a ``parse`` query might accept as
an argument a ``UniqueString path`` and return a vector of owned AST nodes.
Another example is a query to determine the location of an AST node; it would
accept as an argument a ``BaseAST*`` and it would return a Location.

When running a query, the query system will manage:
 * checking to see if the query result is already saved and available for reuse
 * recording the queries called by that query as dependencies

To write a query, create a function that uses the ``QUERY_`` macros defined in
query-impl.h. The arguments to the function need to be efficient to copy (so
``UniqueString``, ``ID``, ``Location``, and pointers are OK, but e.g.
``std::vector`` is not).  The function will return a result, which need not be
POD and can include AST pointers (but see below). The function needs to be
written in a stylized way to interact with the context.

Queries should not have side effects. They should not manipulate global state.
Instead, they should return a result that includes all of the output.

For example, here is a query that computes MyResultType from myArg1 and
myArg2:

.. code-block:: c++

    #include "chpl/queries/query-impl.h"

    const MyResultType& myQueryFunction(Context* context,
                                        MyArgType MyArg1,
                                        MyOtherArgType MyArg2) {
      QUERY_BEGIN(myQueryFunction, context, myKey1, myKey2)

      // do steps to compute the result
      MyResultType result = ...;
      // if an error is encountered, it can be saved with QUERY_ERROR(error)

      return QUERY_END(result);
    }

To call the query, just write e.g. ``myQueryFunction(context, arg1, arg2)``.

The query function will check for a result already stored in the program
database that can be reused. If a result is reused, QUERY_BEGIN will return that
result. If not, the query proceeds to compute the result. When doing so, any
queries called will be automatically recorded as dependencies. It will then
compare the computed result with the saved result, if any, and in some cases
combine the results. Finally, the saved result (which might have been updated)
is returned.

Note that a query must currently return a const-reference to the result to be
stored in the program database.

There are some requirements on query argument/key types and on result types:

 * argument/key types must have ``std::hash<KeyType>``
 * argument/key types must have ``std::equal_to<KeyType>``
 * result types must have ``chpl::update<MyResultType>`` implemented
 * result types must be default constructable
 * If the result contains or refers to any UniqueString, the result type
   must have ``chpl::mark<MyResultType>`` implemented to call ``mark``
   on the UniqueString(s).

.. code-block:: c++

    namespace std {
      template<> struct hash<chpl::MyArgType> {
        size_t operator()(const chpl::MyArgType key) const {
          return doSomethingToComputeHash...;
        }
      };
      template<> struct equal_to<chpl::MyArgType> {
        bool operator()(const chpl::MyArgType lhs,
                        const chpl::MyArgType rhs) const {
          return doSomethingToCheckIfEqual...;
        }
      };
    }

The process of computing a query and checking to see if it matches a saved
result requires that the result type implement ``chpl::update`` and
possible ``chpl::mark``:

.. code-block:: c++

    namespace chpl {
      template<> struct update<MyResultType> {
        bool operator()(chpl::MyResultType& keep,
                        chpl::MyResultType& addin) const {
          return doSomethingToCombine...;
        }
        template<> struct mark<MyResultType> {
        void operator()(Context* context,
                        chpl::MyResultType& keep) const {
          keep.markUniqueStrings(context);
        }
      };

On entry to the ``update`` function, ``keep`` is the current value in the
program database and ``addin`` is the newly computed value. The ``update``
function needs to:

  * store the current, updated result in ``keep``
  * store the unused result in ``addin``
  * return ``false`` if ``keep`` matched ``addin`` -- that is, ``keep`` did not
    need to be updated; and ``true`` otherwise.

For most result types, ``return defaultCombine(keep, addin);`` should be
sufficient. In the event that a result is actually a collection of results
that *owns* the elements (for example, when parsing, the result is
conceptually a vector of top-level symbol), the ``combine`` function
should try to update only those elements of ``keep`` that changed by swapping
in the appropriate elements from ``addin``. This strategy allows later queries
that depend on such a result to use pointers to the owned elements and to
avoid updating everything if just one element changed.

Queries *can* return results that contain non-owning pointers to ``owned``
results from other queries. However, it is not sufficient to simply use the
address of the `const &` result of the query - that is a location in the map
that will not change as the result is updated. Instead, such patterns should
use `owned` to make sure a new heap-allocated value is created.

When working with results containing pointers, the update function should not
rely on the contents of these pointers from the ``keep`` value. The system will
make sure that they refer to valid memory but they might be a combination of old
results.  Additionally, the system will ensure that any old results being
replaced will remain allocated until the garbage collection runs outside of any
query.

For example, a ``parse`` query might result in a list of ``owned`` AST element
pointers. A follow-on query, ``listSymbols``, can result in something containing
these AST element pointers, but not owning them. In that event, the
``listSymbols`` query needs to use a ``update`` function that does not look
into the AST element pointers. However it can compare the pointers themselves
because the ``parse`` query will update the pointer if the contents change.

In some situations, the query framework can reuse a result without running the
``update`` function for it. That can happen when all dependencies have been
checked in this revision and the dependencies are all reused. In that event, the
UniqueStrings that are contained in or referred to by the result need to be
marked so that any UniqueStrings not used can be garbage collected. This is
accomplished by calling the ``mark`` function.

\endrst

 */
class Context {
 private:
  // map that supports uniqueCString / UniqueString
  using UniqueStringsTableType = std::unordered_set<chpl::detail::StringAndLength, chpl::detail::UniqueStrHash, chpl::detail::UniqueStrEqual>;
  UniqueStringsTableType uniqueStringsTable;

  // Map from a query function pointer to appropriate QueryMap object.
  // Maps to an 'owned' heap-allocated thing to manage having subclasses
  // without slicing.
  // It assumes that the query name is already unique.
  std::unordered_map<const void*, owned<querydetail::QueryMapBase>> queryDB;

  // Since IDs include module names but not file paths, use this
  // map to go from module name to file path.
  // (If this proves too restrictive for some reason, we could
  //  start including file path in IDs).
  std::unordered_map<UniqueString, UniqueString> modNameToFilepath;

  std::vector<const querydetail::QueryMapResultBase*> queryStack;

  querydetail::RevisionNumber currentRevisionNumber = 1;
  bool enableDebugTracing = false;
  bool breakSet = false;
  size_t breakOnHash = 0;
  int numQueriesRunThisRevision_ = 0;

  static void defaultReportError(const ErrorMessage& err);
  void (*reportError)(const ErrorMessage& err) = defaultReportError;

  // The following are only used for UniqueString garbage collection
  querydetail::RevisionNumber lastPrepareToGCRevisionNumber = 0;
  querydetail::RevisionNumber gcCounter = 1;

  char* setupStringMetadata(char* buf, size_t len);
  const char* getOrCreateUniqueStringWithAllocation(char* buf,
                                                    const char* str,
                                                    size_t len);
  const char* getOrCreateUniqueString(const char* str, size_t len);

  // saves the dependency in the parent query, which is assumed
  // to be at queryStack.back().
  void saveDependencyInParent(const querydetail::QueryMapResultBase* resultEntry);
  void endQueryHandleDependency(const querydetail::QueryMapResultBase* result);

  template<typename ResultType,
           typename... ArgTs>
  querydetail::QueryMap<ResultType, ArgTs...>*
  getMap(const ResultType& (*queryFunction)(Context* context, ArgTs...),
         const std::tuple<ArgTs...>& tupleOfArgs,
         const char* traceQueryName,
         bool isInputQuery);

  // if the result is present in the map, getResult returns it.
  // if not, it adds a new default-constructed result to the map
  // which will have lastChecked and lastChanged set to -1.
  template<typename ResultType,
           typename... ArgTs>
  const querydetail::QueryMapResult<ResultType, ArgTs...>*
  getResult(querydetail::QueryMap<ResultType, ArgTs...>* queryMap,
            const std::tuple<ArgTs...>& tupleOfArgs);

  void haltForRecursiveQuery(const querydetail::QueryMapResultBase* r);

  template<typename ResultType,
           typename... ArgTs>
  const querydetail::QueryMapResult<ResultType, ArgTs...>*
  updateResultForQueryMapR(
      querydetail::QueryMap<ResultType, ArgTs...>* queryMap,
      const querydetail::QueryMapResult<ResultType, ArgTs...>* r,
      const std::tuple<ArgTs...>& tupleOfArgs,
      ResultType result,
      bool forSetter);

  template<typename ResultType,
           typename... ArgTs>
  const querydetail::QueryMapResult<ResultType, ArgTs...>*
  updateResultForQueryMap(
      querydetail::QueryMap<ResultType, ArgTs...>* queryMap,
      const std::tuple<ArgTs...>& tupleOfArgs,
      ResultType result,
      bool forSetter);

  template<typename ResultType,
           typename... ArgTs>
  const querydetail::QueryMapResult<ResultType, ArgTs...>*
  updateResultForQuery(
       const ResultType& (*queryFunction)(Context* context, ArgTs...),
       const std::tuple<ArgTs...>& tupleOfArgs,
       ResultType result,
       const char* traceQueryName,
       bool isInputQuery,
       bool forSetter);

  template<typename ResultType,
           typename... ArgTs>
  bool
  hasResultForQuery(
       const ResultType& (*queryFunction)(Context* context, ArgTs...),
       const std::tuple<ArgTs...>& tupleOfArgs,
       const char* traceQueryName);

  void recomputeIfNeeded(const querydetail::QueryMapResultBase* resultEntry);
  void updateForReuse(const querydetail::QueryMapResultBase* resultEntry);

  bool queryCanUseSavedResultAndPushIfNot(
            const void* queryFunction,
            const querydetail::QueryMapResultBase* resultEntry);

  // Future Work: make the context thread-safe

  // Future Work: allow moving some AST to a different context
  //              (or, at least, that can handle the unique strings)

  // Performance: Add fine-grained timing to measure
  //  * the total time spent in each query
  //  * the time spent in each query in Context functions
  //    (i.e. hashtable manipulations)
  //  * the time spent in each query in other queries
  //  * the time spent in each query in other query code

  // Performance: How can we arrange for better locality of reference/
  // cache reuse for the maps from IDs? The IDs within a function could
  // be just stored in a vector, but that would add an indirection to
  // the hashtable. Is there a way to adjust the hashing function and
  // tune the hashtable bucket size, or something? Do we need a custom
  // hashtable?

 public:
  /**
    Create a new AST Context.
   */
  Context() = default;
  ~Context();

  /**
   Set the error handling function
   */
  void setErrorHandler(void (*reportError)(const ErrorMessage& err))
  {
    this->reportError = reportError;
  }

  /**

    Get or create a unique string and return it as a C string. If the passed
    string is NULL, this function will return an empty string.

    Unique strings are limited to 2**31 bytes.

    The returned string will store len bytes, even if there are interior
    NULL bytes. It will be NULL terminated either way.

    Strings returned by this function will always be aligned to 2 bytes.

    The function `UniqueString::build` returns such a string
    with a wrapper type. It should be preferred for type safety
    and to reduce redundant checks.
   */
  const char* uniqueCString(const char* s, size_t len);
  /**
    Calls uniqueCString with len=strlen(s). This simpler
    call can be used for C strings that don't contain zero bytes
    other than the terminator.
   */
  const char* uniqueCString(const char* s);
  /**
    Get or create a unique string by concatenating up to 9 strings
    with lengths.
   */
  const char* uniqueCStringConcatLen(const char* s1, size_t len1,
                                     const char* s2, size_t len2,
                                     const char* s3 = nullptr, size_t len3 = 0,
                                     const char* s4 = nullptr, size_t len4 = 0,
                                     const char* s5 = nullptr, size_t len5 = 0,
                                     const char* s6 = nullptr, size_t len6 = 0,
                                     const char* s7 = nullptr, size_t len7 = 0,
                                     const char* s8 = nullptr, size_t len8 = 0,
                                     const char* s9 = nullptr, size_t len9 = 0);
  /**
    Get or create a unique string by concatenating up to 9 strings.
   */
  const char* uniqueCStringConcat(const char* s1,
                                  const char* s2,
                                  const char* s3 = nullptr,
                                  const char* s4 = nullptr,
                                  const char* s5 = nullptr,
                                  const char* s6 = nullptr,
                                  const char* s7 = nullptr,
                                  const char* s8 = nullptr,
                                  const char* s9 = nullptr);



  /**
   When the context is configured to run with garbage collection
   enabled, unique strings that are reused need to be marked.
   This function does that for a C string stored in the map.
   It will cause program crashes if called on a string that
   is not the result of one of the uniqueCString calls.
   */
  void markUniqueCString(const char* s);

  /**
   For a unique string, return the length of the string when it was created.
   It will cause program crashes if called on a string that
   is not the result of one of the uniqueCString calls.
   */
  static size_t lengthForUniqueString(const char* s);

  /**
    Return the file path for the file containing this ID.
   */
  UniqueString filePathForId(ID id);

  /**
    Returns true if filePathForId is already populated for
    this ID.
   */
  bool hasFilePathForId(ID id);

  /**
    This function increments the current revision number stored
    in the context. After it is called, the setters below can
    be used to provide the input at that revision.

    If the prepareToGC argument is true, when processing queries
    in that revision, will prepare to garbage collect UniqueStrings
    (by marking elements appropriately).
   */
  void advanceToNextRevision(bool prepareToGC);

  /**
    Returns the number of query bodies executed in this revision.
   */
  int numQueriesRunThisRevision() const {
    return numQueriesRunThisRevision_;
  }

  /**
    This function runs garbage collection. It will collect UniqueStrings
    if the last call to advanceToNextRevision passed prepareToGC=true.

    It is an implementation error to call this function while a query
    is running.
   */
  void collectGarbage();

  // setters for named queries.

  /**
    Sets the file path for the given module ID. This
    is suitable to call from a parse query.
   */
  void setFilePathForModuleID(ID moduleID, UniqueString path);

  /**
    Note an error for the currently running query and report it
    with the error handler set by setErrorHandler.

    If no query is currently running, it just reports the error.
   */
  void error(ErrorMessage error);

  /**
    Note an error for the currently running query.
    This is a convenience overload.
    This version takes in a Location and a printf-style format string.
   */
  void error(Location loc, const char* fmt, ...)
  #ifndef DOXYGEN
    // docs generator has trouble with the attribute applied to 'build'
    // so the above ifndef works around the issue.
    __attribute__ ((format (printf, 3, 4)))
  #endif
  ;

  /**
    Note an error for the currently running query.
    This is a convenience overload.
    This version takes in an ID and a printf-style format string.
    The ID is used to compute a Location using parsing::locateId.
   */
  void error(ID id, const char* fmt, ...)
  #ifndef DOXYGEN
    // docs generator has trouble with the attribute applied to 'build'
    // so the above ifndef works around the issue.
    __attribute__ ((format (printf, 3, 4)))
  #endif
  ;

  /**
    Note an error for the currently running query.
    This is a convenience overload.
    This version takes in an AST node and a printf-style format string.
    The AST node is used to compute a Location by using a parsing::locateAst.
   */
  void error(const uast::ASTNode* ast, const char* fmt, ...)
  #ifndef DOXYGEN
    // docs generator has trouble with the attribute applied to 'build'
    // so the above ifndef works around the issue.
    __attribute__ ((format (printf, 3, 4)))
  #endif
  ;

  /**
    Note an error for the currently running query.
    This is a convenience overload.
    This version takes in a TypedFnSignature and an AST node and a
    printf-style format string.
    The AST node is used to compute a Location by using a parsing::locateAst.
    The TypedFnSignature is used to print out instantiation information.
   */
  void error(const resolution::TypedFnSignature* inFn,
             const uast::ASTNode* ast,
             const char* fmt, ...)
  #ifndef DOXYGEN
    // docs generator has trouble with the attribute applied to 'build'
    // so the above ifndef works around the issue.
    __attribute__ ((format (printf, 4, 5)))
  #endif
  ;

  typedef enum {
    NOT_CHECKED_NOT_CHANGED = 0,
    REUSED = 1,
    CHANGED = 2
  } QueryStatus;

  /**
    Returns:
      0 if the query was not checked or changed in this revision
      1 if the query was checked but not changed in this revision
      2 if the query was changed in this revision

    This is intended only as a debugging aid.
   */
  template<typename ResultType,
           typename... ArgTs>
  QueryStatus queryStatus(
         const ResultType& (*queryFunction)(Context* context, ArgTs...),
         const std::tuple<ArgTs...>& tupleOfArgs);

  // the following functions are called by the macros defined in QueryImpl.h
  // and should not be called directly

  /// \cond DO_NOT_DOCUMENT
  template<typename... ArgTs>
  void queryBeginTrace(const char* traceQueryName,
                       const std::tuple<ArgTs...>& tupleOfArg);

  template<typename ResultType,
           typename... ArgTs>
  querydetail::QueryMap<ResultType, ArgTs...>*
  queryBeginGetMap(
       const ResultType& (*queryFunction)(Context* context, ArgTs...),
       const std::tuple<ArgTs...>& tupleOfArgs,
       const char* traceQueryName,
       bool isInputQuery);

  template<typename ResultType,
           typename... ArgTs>
  const querydetail::QueryMapResult<ResultType, ArgTs...>*
  queryBeginGetResult(querydetail::QueryMap<ResultType, ArgTs...>* queryMap,
                      const std::tuple<ArgTs...>& tupleOfArgs);


  template<typename ResultType,
           typename... ArgTs>
  bool queryUseSaved(
         const ResultType& (*queryFunction)(Context* context, ArgTs...),
         const querydetail::QueryMapResult<ResultType, ArgTs...>* r,
         const char* traceQueryName);

  template<typename ResultType, typename... ArgTs>
  const ResultType&
  queryGetSaved(const querydetail::QueryMapResult<ResultType, ArgTs...>* r);

  // It's a fatal error to run a query recursively.
  // To avoid that in cases that have some sort of natural recursion,
  // use this function to ask if a query is already running and to
  // get the partial result if it is.
  template<typename ResultType,
           typename... ArgTs>
  const ResultType* queryGetRunningQueryPartialResult(
         const ResultType& (*queryFunction)(Context* context, ArgTs...),
         const std::tuple<ArgTs...>& tupleOfArgs,
         const char* traceQueryName);

  template<typename ResultType,
           typename... ArgTs>
  const ResultType& queryEnd(
      const ResultType& (*queryFunction)(Context* context, ArgTs...),
      querydetail::QueryMap<ResultType, ArgTs...>* queryMap,
      const querydetail::QueryMapResult<ResultType, ArgTs...>* r,
      const std::tuple<ArgTs...>& tupleOfArgs,
      ResultType result,
      const char* traceQueryName);

  template<typename ResultType,
           typename... ArgTs>
  const ResultType& queryEndCurrentResult(
      const ResultType& (*queryFunction)(Context* context, ArgTs...),
      querydetail::QueryMap<ResultType, ArgTs...>* queryMap,
      const querydetail::QueryMapResult<ResultType, ArgTs...>* r,
      const std::tuple<ArgTs...>& tupleOfArgs,
      const char* traceQueryName);

  template<typename ResultType,
           typename... ArgTs>
  void querySetterUpdateResult(
      const ResultType& (*queryFunction)(Context* context, ArgTs...),
      const std::tuple<ArgTs...>& tupleOfArgs,
      ResultType result,
      const char* traceQueryName,
      bool isInputQuery);


  /// \endcond
};

} // end namespace chpl

#endif
