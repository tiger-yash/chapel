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

#include "chpl/uast/Function.h"

#include "chpl/uast/Block.h"
#include "chpl/uast/Builder.h"

namespace chpl {
namespace uast {


owned<Function> Function::build(Builder* builder, Location loc,
                                owned<Attributes> attributes,
                                Decl::Visibility vis,
                                Function::Linkage linkage,
                                owned<Expression> linkageNameExpr,
                                UniqueString name,
                                bool inline_,
                                bool override_,
                                Function::Kind kind,
                                owned<Formal> receiver,
                                Function::ReturnIntent returnIntent,
                                bool throws,
                                bool primaryMethod,
                                bool parenless,
                                ASTList formals,
                                owned<Expression> returnType,
                                owned<Expression> where,
                                ASTList lifetime,
                                owned<Block> body) {
  ASTList lst;

  int attributesChildNum = -1;
  int linkageNameExprChildNum = -1;
  int formalsChildNum = -1;
  int thisFormalChildNum = -1;
  int numFormals = 0;
  int returnTypeChildNum = -1;
  int whereChildNum = -1;
  int lifetimeChildNum = -1;
  int numLifetimeParts = 0;
  int bodyChildNum = -1;

  if (attributes.get() != nullptr) {
    attributesChildNum = lst.size();
    lst.push_back(std::move(attributes));
  }

  if (linkageNameExpr.get() != nullptr) {
    linkageNameExprChildNum = lst.size();
    lst.push_back(std::move(linkageNameExpr));
  }

  if (receiver.get() == nullptr && formals.size() == 0) {
    // leave formalsChildNum == -1
  } else {
    formalsChildNum = lst.size();
    if (receiver.get() != nullptr) {
      thisFormalChildNum = lst.size();
      lst.push_back(std::move(receiver));
      numFormals++;
    }
    int nFormals = formals.size();
    for (auto & formal : formals) {
      lst.push_back(std::move(formal));
    }
    numFormals += nFormals;
  }

  if (returnType.get() != nullptr) {
    returnTypeChildNum = lst.size();
    lst.push_back(std::move(returnType));
  }
  if (where.get() != nullptr) {
    whereChildNum = lst.size();
    lst.push_back(std::move(where));
  }
  numLifetimeParts = lifetime.size();
  if (numLifetimeParts != 0) {
    lifetimeChildNum = lst.size();
    for (auto & part : lifetime) {
      lst.push_back(std::move(part));
    }
  }

  if (body.get() != nullptr) {
    bodyChildNum = lst.size();
    lst.push_back(std::move(body));
  }

  Function* ret = new Function(std::move(lst), attributesChildNum, vis,
                               linkage,
                               name,
                               inline_,
                               override_,
                               kind,
                               returnIntent,
                               throws,
                               primaryMethod,
                               parenless,
                               linkageNameExprChildNum,
                               formalsChildNum,
                               thisFormalChildNum,
                               numFormals,
                               returnTypeChildNum,
                               whereChildNum,
                               lifetimeChildNum,
                               numLifetimeParts,
                               bodyChildNum);
  builder->noteLocation(ret, loc);
  return toOwned(ret);
}


} // namespace uast
} // namespace chpl
