/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-2014, Open Source Modelica Consortium (OSMC),
 * c/o Linköpings universitet, Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 LICENSE OR
 * THIS OSMC PUBLIC LICENSE (OSMC-PL) VERSION 1.2.
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES
 * RECIPIENT'S ACCEPTANCE OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3,
 * ACCORDING TO RECIPIENTS CHOICE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from OSMC, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or
 * http://www.openmodelica.org, and in the OpenModelica distribution.
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */

encapsulated uniontype NFExpandExp
  import Expression = NFExpression;

protected
  import RangeIterator = NFRangeIterator;
  import ExpressionIterator = NFExpressionIterator;
  import Subscript = NFSubscript;
  import Type = NFType;
  import Call = NFCall;
  import NFCallAttributes;
  import Dimension = NFDimension;
  import ComponentRef = NFComponentRef;
  import NFFunction.Function;
  import Operator = NFOperator;
  import Ceval = NFCeval;
  import NFInstNode.InstNode;
  import SimplifyExp = NFSimplifyExp;
  import NFPrefixes.{Variability, Purity};
  import MetaModelica.Dangerous.*;
  import EvalTarget = NFCeval.EvalTarget;
  import Array;

public
  function expand
    input output Expression exp;
    input Boolean backend = false;
          output Boolean expanded;
  algorithm
    (exp, expanded) := match exp
      local
        array<Expression> arr;

      case Expression.INTEGER()      then (exp, true);
      case Expression.REAL()         then (exp, true);
      case Expression.STRING()       then (exp, true);
      case Expression.BOOLEAN()      then (exp, true);
      case Expression.ENUM_LITERAL() then (exp, true);

      case Expression.CREF(ty = Type.ARRAY()) then expandCref(exp, backend);

      // One-dimensional arrays are already expanded.
      case Expression.ARRAY() guard Type.isVector(exp.ty) then (exp, true);

      case Expression.ARRAY()
        algorithm
          (arr, expanded) := expandArray(exp.elements);
          exp.elements := arr;
        then
          (exp, expanded);

      case Expression.TYPENAME() then (expandTypename(exp.ty), true);
      case Expression.RANGE()    then expandRange(exp);
      case Expression.CALL()     then expandCall(exp.call, exp, backend);
      case Expression.SIZE()     then expandSize(exp);
      case Expression.BINARY()   then expandBinary(exp, exp.operator, backend);
      case Expression.MULTARY()  then expand(SimplifyExp.splitMultary(exp), backend);
      case Expression.UNARY()    then expandUnary(exp);
      case Expression.LBINARY()  then expandLogicalBinary(exp);
      case Expression.LUNARY()   then expandLogicalUnary(exp);
      case Expression.RELATION() then (exp, true);
      case Expression.CAST()     then expandCast(exp);
      case Expression.FILENAME() then (exp, true);
      else expandGeneric(exp, backend);
    end match;
  end expand;

  function expandArray
    "Expands an array of Expressions."
    input array<Expression> arr;
    output array<Expression> outArray;
    output Boolean expanded = true;
  protected
    Boolean res;
    Expression e;
  algorithm
    outArray := arrayCopy(arr);

    for i in 1:arrayLength(outArray) loop
      (e, res) := expand(arrayGetNoBoundsChecking(outArray, i));

      if not res then
        expanded := false;
        return;
      end if;

      arrayUpdateNoBoundsChecking(outArray, i, e);
    end for;
  end expandArray;

  function expandList
    "Expands a list of Expressions. If abortOnFailure is true the function will
     stop if it fails to expand an element and the original list will be
     returned unchanged. If abortOnFailure is false it will instead continue and
     try to expand the whole list. In both cases the output 'expanded' indicates
     whether the whole list could be expanded or not."
    input list<Expression> expl;
    input Boolean abortOnFailure = true;
    output list<Expression> outExpl = {};
    output Boolean expanded = true;
  protected
    Boolean res;
  algorithm
    for exp in expl loop
      (exp, res) := expand(exp);
      expanded := res and expanded;

      if not res and abortOnFailure then
        outExpl := expl;
        return;
      end if;

      outExpl := exp :: outExpl;
    end for;

    outExpl := listReverseInPlace(outExpl);
  end expandList;

  function expandCref
    input Expression crefExp;
    input Boolean backend = false;
    output Expression arrayExp;
    output Boolean expanded;
  protected
    list<list<Subscript>> subs;
  algorithm
    (arrayExp, expanded) := match crefExp
      case Expression.CREF(cref = ComponentRef.CREF())
        algorithm
          if Type.hasZeroDimension(crefExp.ty) then
            arrayExp := Expression.makeEmptyArray(crefExp.ty);
            expanded := true;
          elseif Type.hasKnownSize(crefExp.ty) then
            subs := expandCref2(crefExp.cref, backend);
            arrayExp := expandCref3(subs, crefExp.cref, Type.arrayElementType(crefExp.ty));
            expanded := true;
          else
            arrayExp := crefExp;
            expanded := false;
          end if;
        then
          (arrayExp, expanded);

      else (crefExp, false);
    end match;
  end expandCref;

  function expandCref2
    input ComponentRef cref;
    input Boolean backend;
    input output list<list<Subscript>> subs = {};
  protected
    list<Subscript> cr_subs = {};
    list<Dimension> dims;

    import NFComponentRef.Origin;
  algorithm
    subs := match cref
      case ComponentRef.CREF() guard(backend or cref.origin == Origin.CREF)
        algorithm
          dims := Type.arrayDims(cref.ty);
          cr_subs := Subscript.expandList(cref.subscripts, dims, backend);
        then
          if listEmpty(cr_subs) and not listEmpty(dims) then
            {} else expandCref2(cref.restCref, backend, cr_subs :: subs);

      else subs;
    end match;
  end expandCref2;

  function expandCref3
    input list<list<Subscript>> subs;
    input ComponentRef cref;
    input Type crefType;
    input list<list<Subscript>> accum = {};
    output Expression arrayExp;
  algorithm
    arrayExp := match subs
      case {} then Expression.CREF(crefType, ComponentRef.setSubscriptsList(accum, cref));
      else expandCref4(listHead(subs), {}, accum, listRest(subs), cref, crefType);
    end match;
  end expandCref3;

  function expandCref4
    input list<Subscript> subs;
    input list<Subscript> comb = {};
    input list<list<Subscript>> accum = {};
    input list<list<Subscript>> restSubs;
    input ComponentRef cref;
    input Type crefType;
    output Expression arrayExp;
  protected
    array<Expression> expl;
    Type arr_ty;
    list<Subscript> slice, rest;
    Integer i;
  algorithm
    arrayExp := match subs
      case {} then expandCref3(restSubs, cref, crefType, listReverse(comb) :: accum);

      case Subscript.EXPANDED_SLICE(indices = slice) :: rest
        algorithm
          expl := arrayCreateNoInit(listLength(slice), Expression.INTEGER(0));
          i := 1;

          for idx in slice loop
            arrayUpdateNoBoundsChecking(expl, i,
              expandCref4(rest, idx :: comb, accum, restSubs, cref, crefType));
            i := i + 1;
          end for;

          arr_ty := Type.liftArrayLeft(Expression.typeOf(arrayGet(expl, 1)), Dimension.fromExpArray(expl));
        then
          Expression.makeArray(arr_ty, expl);

      else expandCref4(listRest(subs), listHead(subs) :: comb, accum, restSubs, cref, crefType);
    end match;
  end expandCref4;

  function expandTypename
    input Type ty;
    output Expression outExp;
  algorithm
    outExp := match ty
      local
        list<Expression> lits;

      case Type.ARRAY(elementType = Type.BOOLEAN())
        then Expression.makeArray(ty, listArray({Expression.BOOLEAN(false), Expression.BOOLEAN(true)}), true);

      case Type.ARRAY(elementType = Type.ENUMERATION())
        algorithm
          lits := Expression.makeEnumLiterals(ty.elementType);
        then
          Expression.makeArray(ty, listArray(lits), true);

      else
        algorithm
          Error.addInternalError(getInstanceName() + " got invalid typename", sourceInfo());
        then
          fail();
    end match;
  end expandTypename;

  function expandRange
    input Expression exp;
    output Expression outExp;
    output Boolean expanded;
  protected
    RangeIterator range_iter;
    Type ty;
  algorithm
    Expression.RANGE(ty = ty) := exp;
    expanded := Expression.isLiteral(exp);

    if expanded then
      outExp := Ceval.evalExp(exp);
    else
      outExp := exp;
    end if;
  end expandRange;

  function expandCall
    input Call call;
    input Expression exp;
    input Boolean resize;
    output Expression outExp;
    output Boolean expanded;
  algorithm
    (outExp, expanded) := matchcontinue call
      case Call.TYPED_CALL()
        guard Function.isBuiltin(call.fn) and not Function.isImpure(call.fn)
        then expandBuiltinCall(call.fn, call.arguments, call, resize);

      case Call.TYPED_ARRAY_CONSTRUCTOR()
        then expandArrayConstructor(call.exp, call.ty, call.iters);

      else expandGeneric(exp, resize);
    end matchcontinue;
  end expandCall;

  function expandBuiltinCall
    input Function fn;
    input list<Expression> args;
    input Call call;
    input Boolean resize;
    output Expression outExp;
    output Boolean expanded;
  protected
    Absyn.Path fn_path = Function.nameConsiderBuiltin(fn);
  algorithm
    (outExp, expanded) := match AbsynUtil.pathFirstIdent(fn_path)
      case "cat"        then expandBuiltinCat(args, call, resize);
      case "der"        then expandBuiltinGeneric(call);
      case "diagonal"   then expandBuiltinDiagonal(listHead(args));
      case "fill"       then expandBuiltinFill(args);
      case "pre"        then expandBuiltinGeneric(call);
      case "previous"   then expandBuiltinGeneric(call);
      case "promote"    then expandBuiltinPromote(args);
      case "transpose"  then expandBuiltinTranspose(listHead(args));
    end match;
  end expandBuiltinCall;

  function expandBuiltinCat
    input list<Expression> args;
    input Call call;
    input Boolean resize;
    output Expression exp;
    output Boolean expanded;
  protected
    list<Expression> expl = {};
  algorithm
    (expl, expanded) := expandList(listRest(args));

    if expanded then
      // This relies on the fact that Ceval.evalBuiltinCat doesn't actually do any
      // actual constant evaluation, and works on non-constant arrays too as long
      // as they're expanded.
      exp := Ceval.evalBuiltinCat(listHead(args), expl, NFCeval.noTarget);
    else
      exp := expandGeneric(Expression.CALL(call), resize);
    end if;
  end expandBuiltinCat;

  function expandBuiltinPromote
    input list<Expression> args;
    output Expression exp;
    output Boolean expanded;
  protected
    Integer n;
    Expression eexp, nexp;
  algorithm
    eexp :: nexp :: {} := args;
    Expression.INTEGER(value = n) := nexp;
    (eexp, expanded) := expand(eexp);
    exp := Expression.promote(eexp, Expression.typeOf(eexp), n);
  end expandBuiltinPromote;

  function expandBuiltinDiagonal
    input Expression arg;
    output Expression outExp;
    output Boolean expanded;
  algorithm
    (outExp, expanded) := expand(arg);

    if expanded then
      outExp := Ceval.evalBuiltinDiagonal(outExp);
    end if;
  end expandBuiltinDiagonal;

  function expandBuiltinFill
    input list<Expression> args;
    output Expression outExp;
    output Boolean expanded = true;
  algorithm
    outExp := Expression.fillArgs(listHead(args), listRest(args));
  end expandBuiltinFill;

  function expandBuiltinTranspose
    input Expression arg;
    output Expression outExp;
    output Boolean expanded;
  algorithm
    (outExp, expanded) := expand(arg);

    if expanded then
      outExp := Expression.transposeArray(outExp);
    end if;
  end expandBuiltinTranspose;

  function expandBuiltinGeneric
    input Call call;
    output Expression outExp;
    output Boolean expanded = true;
  protected
    Function fn;
    Type ty;
    Variability var;
    Purity pur;
    NFCallAttributes attr;
    Expression arg;
    list<Expression> args;
  algorithm
    Call.TYPED_CALL(fn, ty, var, pur, {arg}, attr) := call;
    ty := Type.arrayElementType(ty);

    (arg, true) := expand(arg);
    outExp := expandBuiltinGeneric2(arg, fn, ty, var, pur, attr);
  end expandBuiltinGeneric;

  function expandBuiltinGeneric2
    input output Expression exp;
    input Function fn;
    input Type ty;
    input Variability var;
    input Purity pur;
    input NFCallAttributes attr;
  algorithm
    exp := match exp
      local
        array<Expression> arr;

      case Expression.ARRAY(literal = true) then exp;

      case Expression.ARRAY()
        algorithm
          arr := Array.map(exp.elements,
            function expandBuiltinGeneric2(fn = fn, ty = ty, var = var, pur = pur, attr = attr));
        then
          Expression.makeArray(Type.setArrayElementType(exp.ty, ty), arr);

      else Expression.CALL(Call.TYPED_CALL(fn, ty, var, pur, {exp}, attr));
    end match;
  end expandBuiltinGeneric2;

  function expandArrayConstructor
    input Expression exp;
    input Type ty;
    input list<tuple<InstNode, Expression>> iterators;
    output Expression result;
    output Boolean expanded = true;
  protected
    Expression e = exp, range;
    InstNode node;
    list<Expression> ranges = {};
    Mutable<Expression> iter;
    list<Mutable<Expression>> iters = {};
  algorithm
    for i in iterators loop
      (node, range) := i;
      iter := Mutable.create(Expression.EMPTY(InstNode.getType(node)));
      e := Expression.replaceIterator(e, node, Expression.MUTABLE(iter));
      iters := iter :: iters;
      (range, true) := expand(range);
      ranges := range :: ranges;
    end for;

    result := expandArrayConstructor2(e, ty, ranges, iters);
  end expandArrayConstructor;

  function expandArrayConstructor2
    input Expression exp;
    input Type ty;
    input list<Expression> ranges;
    input list<Mutable<Expression>> iterators;
    output Expression result;
  protected
    Expression range;
    list<Expression> ranges_rest, expl = {};
    Mutable<Expression> iter;
    list<Mutable<Expression>> iters_rest;
    ExpressionIterator range_iter;
    Expression value;
    Type el_ty;
  algorithm
    if listEmpty(ranges) then
      // Normally it wouldn't be the expansion's task to simplify expressions,
      // but we make an exception here since the generated expressions contain
      // MUTABLE expressions that we need to get rid of. Also, expansion of
      // array constructors is often done during the scalarization phase, after
      // the simplification phase, so they wouldn't otherwise be simplified.
      result := expand(SimplifyExp.simplify(exp));
    else
      range :: ranges_rest := ranges;
      iter :: iters_rest := iterators;
      range_iter := ExpressionIterator.fromExp(range);
      el_ty := Type.unliftArray(ty);

      while ExpressionIterator.hasNext(range_iter) loop
        (range_iter, value) := ExpressionIterator.next(range_iter);
        Mutable.update(iter, value);
        expl := expandArrayConstructor2(exp, el_ty, ranges_rest, iters_rest) :: expl;
      end while;

      result := Expression.makeArray(ty, listArray(listReverseInPlace(expl)));
    end if;
  end expandArrayConstructor2;

  function expandSize
    input Expression exp;
    output Expression outExp;
    output Boolean expanded = true;
  algorithm
    outExp := match exp
      local
        Integer dims;
        Expression e;
        Type ty;
        list<Expression> expl;

      case Expression.SIZE(exp = e, dimIndex = NONE())
        algorithm
          ty := Expression.typeOf(e);
          dims := Type.dimensionCount(ty);
          expl := list(Expression.SIZE(e, SOME(Expression.INTEGER(i))) for i in 1:dims);
        then
          Expression.makeArray(Type.ARRAY(ty, {Dimension.fromInteger(dims)}), listArray(expl));

      // Size with an index is scalar, and thus already maximally expanded.
      else exp;
    end match;
  end expandSize;

  function expandBinary
    input Expression exp;
    input Operator op;
    input Boolean resize;
    output Expression outExp;
    output Boolean expanded;

    import NFOperator.Op;
  algorithm
    (outExp, expanded) := match op.op
      case Op.ADD_SCALAR_ARRAY  then expandBinaryScalarArray(exp, Op.ADD);
      case Op.ADD_ARRAY_SCALAR  then expandBinaryArrayScalar(exp, Op.ADD);
      case Op.SUB_SCALAR_ARRAY  then expandBinaryScalarArray(exp, Op.SUB);
      case Op.SUB_ARRAY_SCALAR  then expandBinaryArrayScalar(exp, Op.SUB);
      case Op.MUL_SCALAR_ARRAY  then expandBinaryScalarArray(exp, Op.MUL);
      case Op.MUL_ARRAY_SCALAR  then expandBinaryArrayScalar(exp, Op.MUL);
      case Op.MUL_VECTOR_MATRIX then expandBinaryVectorMatrix(exp);
      case Op.MUL_MATRIX_VECTOR then expandBinaryMatrixVector(exp);
      case Op.SCALAR_PRODUCT    then expandBinaryDotProduct(exp);
      case Op.MATRIX_PRODUCT    then expandBinaryMatrixProduct(exp);
      case Op.DIV_SCALAR_ARRAY  then expandBinaryScalarArray(exp, Op.DIV);
      case Op.DIV_ARRAY_SCALAR  then expandBinaryArrayScalar(exp, Op.DIV);
      case Op.POW_SCALAR_ARRAY  then expandBinaryScalarArray(exp, Op.POW);
      case Op.POW_ARRAY_SCALAR  then expandBinaryArrayScalar(exp, Op.POW);
      case Op.POW_MATRIX        then expandBinaryPowMatrix(exp, resize);
      else                           expandBinaryElementWise(exp);
    end match;

    if not expanded then
      outExp := exp;
    end if;
  end expandBinary;

  function expandBinaryElementWise
    input Expression exp;
    output Expression outExp;
    output Boolean expanded;
  protected
    Expression exp1, exp2;
    Operator op;
  algorithm
    Expression.BINARY(exp1 = exp1, operator = op, exp2 = exp2) := exp;

    if Type.isArray(Operator.typeOf(op)) then
      (exp1, expanded) := expand(exp1);

      if expanded then
        (exp2, expanded) := expand(exp2);
      end if;

      if expanded then
        outExp := expandBinaryElementWise2(exp1, op, exp2, SimplifyExp.simplifyBinaryOp);
      else
        outExp := exp;
      end if;
    else
      outExp := exp;
      expanded := true;
    end if;
  end expandBinaryElementWise;

  function expandBinaryElementWise2
    input Expression exp1;
    input Operator op;
    input Expression exp2;
    input MakeFn func;
    output Expression exp;

    partial function MakeFn
      input Expression exp1;
      input Operator op;
      input Expression exp2;
      output Expression exp;
    end MakeFn;
  protected
    array<Expression> expl1, expl2, expl;
    Type ty;
    Operator eop;
  algorithm
    expl1 := Expression.arrayElements(exp1);
    expl2 := Expression.arrayElements(exp2);
    ty := Operator.typeOf(op);
    eop := Operator.setType(Type.unliftArray(ty), op);

    if Type.dimensionCount(ty) > 1 then
      expl := Array.threadMap(expl1, expl2, function expandBinaryElementWise2(op = eop, func = func));
    else
      expl := Array.threadMap(expl1, expl2, function func(op = eop));
      //expl := list(func(e1, eop, e2) threaded for e1 in expl1, e2 in expl2);
    end if;

    exp := Expression.makeArray(ty, expl);
  end expandBinaryElementWise2;

  function expandBinaryScalarArray
    input Expression exp;
    input NFOperator.Op scalarOp;
    output Expression outExp;
    output Boolean expanded;
  protected
    Expression exp1, exp2;
    Operator op;
  algorithm
    Expression.BINARY(exp1 = exp1, operator = op, exp2 = exp2) := exp;
    (exp2, expanded) := expand(exp2);

    if expanded then
      op := Operator.OPERATOR(Type.arrayElementType(Operator.typeOf(op)), scalarOp);
      outExp := Expression.mapArrayElements(exp2,
        function SimplifyExp.simplifyBinaryOp(op = op, exp1 = exp1));
    else
      outExp := exp;
    end if;
  end expandBinaryScalarArray;

  function makeScalarArrayBinary_traverser
    input Expression exp1;
    input Operator op;
    input Expression exp2;
    output Expression exp;
  algorithm
    exp := match exp2
      case Expression.ARRAY() then exp2;
      else SimplifyExp.simplifyBinaryOp(exp1, op, exp2);
    end match;
  end makeScalarArrayBinary_traverser;

  function expandBinaryArrayScalar
    input Expression exp;
    input NFOperator.Op scalarOp;
    output Expression outExp;
    output Boolean expanded;
  protected
    Expression exp1, exp2;
    Operator op;
  algorithm
    Expression.BINARY(exp1 = exp1, operator = op, exp2 = exp2) := exp;
    (exp1, expanded) := expand(exp1);

    if expanded then
      op := Operator.OPERATOR(Type.arrayElementType(Operator.typeOf(op)), scalarOp);
      outExp := Expression.mapArrayElements(exp1,
        function SimplifyExp.simplifyBinaryOp(op = op, exp2 = exp2));
    else
      outExp := exp;
    end if;
  end expandBinaryArrayScalar;

  function expandBinaryVectorMatrix
    "Expands a vector*matrix expression, c[m] = a[n] * b[n, m]."
    input Expression exp;
    output Expression outExp;
    output Boolean expanded;
  protected
    Expression exp1, exp2;
    array<Expression> arr;
    Type ty;
    Dimension m;
  algorithm
    Expression.BINARY(exp1 = exp1, exp2 = exp2) := exp;
    (exp2, expanded) := expand(exp2);

    if expanded then
      Expression.ARRAY(Type.ARRAY(ty, {m, _}), arr) := Expression.transposeArray(exp2);
      ty := Type.ARRAY(ty, {m});

      if arrayEmpty(arr) then
        outExp := Expression.makeZero(ty);
      else
        (exp1, expanded) := expand(exp1);

        if expanded then
          // c[i] = a * b[:, i] for i in 1:m
          arr := Array.map(arr, function makeScalarProduct(exp1 = exp1));
          outExp := Expression.makeArray(ty, arr);
        else
          outExp := exp;
        end if;
      end if;
    else
      outExp := exp;
    end if;
  end expandBinaryVectorMatrix;

  function expandBinaryMatrixVector
    "Expands a matrix*vector expression, c[n] = a[n, m] * b[m]."
    input Expression exp;
    output Expression outExp;
    output Boolean expanded;
  protected
    Expression exp1, exp2;
    array<Expression> arr;
    Type ty;
    Dimension n;
  algorithm
    Expression.BINARY(exp1 = exp1, exp2 = exp2) := exp;
    (exp1, expanded) := expand(exp1);

    if expanded then
      Expression.ARRAY(Type.ARRAY(ty, {n, _}), arr) := exp1;
      ty := Type.ARRAY(ty, {n});

      if arrayEmpty(arr) then
        outExp := Expression.makeZero(ty);
      else
        (exp2, expanded) := expand(exp2);

        if expanded then
          // c[i] = a[i, :] * b for i in 1:n
          arr := Array.map(arr, function makeScalarProduct(exp2 = exp2));
          outExp := Expression.makeArray(ty, arr);
        else
          outExp := exp;
        end if;
      end if;
    else
      outExp := exp;
    end if;
  end expandBinaryMatrixVector;

  function expandBinaryDotProduct
    "Expands a vector*vector expression, c = a[n] * b[n]."
    input Expression exp;
    output Expression outExp;
    output Boolean expanded;
  protected
    Expression exp1, exp2;
  algorithm
    Expression.BINARY(exp1 = exp1, exp2 = exp2) := exp;
    (exp1, expanded) := expand(exp1);

    if expanded then
      (exp2, expanded) := expand(exp2);
    end if;

    if expanded then
      outExp := makeScalarProduct(exp1, exp2);
    else
      outExp := exp;
    end if;
  end expandBinaryDotProduct;

  function makeScalarProduct
    input Expression exp1;
    input Expression exp2;
    output Expression exp;
  protected
    array<Expression> arr1, arr2;
    Type ty, elem_ty;
    Operator mul_op, add_op;
  algorithm
    Expression.ARRAY(ty, arr1) := exp1;
    Expression.ARRAY( _, arr2) := exp2;
    elem_ty := Type.unliftArray(ty);

    if arrayEmpty(arr1) then
      // Scalar product of two empty arrays. The result is defined in the spec
      // by sum, so we return 0 since that's the default value of sum.
      exp := Expression.makeZero(elem_ty);
    else
      mul_op := Operator.makeMul(elem_ty);
      add_op := Operator.makeAdd(elem_ty);
      arr1 := Array.threadMap(arr1, arr2, function SimplifyExp.simplifyBinaryOp(op = mul_op));
      exp := Array.reduce(arr1, function SimplifyExp.simplifyBinaryOp(op = add_op));
    end if;
  end makeScalarProduct;

  function expandBinaryMatrixProduct
    "Expands a matrix*matrix expression, c[n, p] = a[n, m] * b[m, p]."
    input Expression exp;
    output Expression outExp;
    output Boolean expanded;
  protected
    Expression exp1, exp2;
  algorithm
    Expression.BINARY(exp1 = exp1, exp2 = exp2) := exp;
    (exp1, expanded) := expand(exp1);

    if expanded then
      (exp2, expanded) := expand(exp2);
    end if;

    if expanded then
      outExp := makeBinaryMatrixProduct(exp1, exp2);
    else
      outExp := exp;
    end if;
  end expandBinaryMatrixProduct;

  function makeBinaryMatrixProduct
    input Expression exp1;
    input Expression exp2;
    output Expression exp;
  protected
    array<Expression> arr1, arr2, arr;
    Type ty, row_ty, mat_ty;
    Dimension n, p;
    Integer len;
    Expression e;
  algorithm
    Expression.ARRAY(Type.ARRAY(ty, {n, _}), arr1) := exp1;
    // Transpose the second matrix. This makes it easier to do the multiplication,
    // since we can do row-row multiplications instead of row-column.
    Expression.ARRAY(Type.ARRAY(dimensions = {p, _}), arr2) := Expression.transposeArray(exp2);
    mat_ty := Type.ARRAY(ty, {n, p});

    if arrayEmpty(arr2) then
      // If any of the matrices' dimensions are zero, the result will be a matrix
      // of zeroes (the default value of sum). Only arr2 needs to be checked here,
      // the normal case can handle arr1 being empty.
      exp := Expression.makeZero(mat_ty);
    else
      // c[i, j] = a[i, :] * b[:, j] for i in 1:n, j in 1:p.
      row_ty := Type.ARRAY(ty, {p});
      len := arrayLength(arr1);
      arr := arrayCreateNoInit(len, exp1);

      for i in 1:len loop
        e := arrayGetNoBoundsChecking(arr1, i);
        arrayUpdateNoBoundsChecking(arr, i,
          Expression.makeArray(row_ty, makeBinaryMatrixProduct2(e, arr2)));
      end for;

      exp := Expression.makeArray(mat_ty, arr);
    end if;
  end makeBinaryMatrixProduct;

  function makeBinaryMatrixProduct2
    input Expression row;
    input array<Expression> matrix;
    output array<Expression> outRow;
  algorithm
    outRow := Array.map(matrix, function makeScalarProduct(exp1 = row));
  end makeBinaryMatrixProduct2;

  function expandBinaryPowMatrix
    input Expression exp;
    input Boolean resize;
    output Expression outExp;
    output Boolean expanded;
  protected
    Expression exp1, exp2;
    Operator op;
    Integer n;
  algorithm
    Expression.BINARY(exp1 = exp1, operator = op, exp2 = exp2) := exp;

    (outExp, expanded) := match exp2
      // a ^ 0 = identity(size(a, 1))
      case Expression.INTEGER(0)
        algorithm
          n := Dimension.size(listHead(Type.arrayDims(Operator.typeOf(op))));
        then
          (Expression.makeIdentityMatrix(n, Type.REAL()), true);

      // a ^ n where n is a literal value.
      case Expression.INTEGER(n)
        guard n > 0
        algorithm
          (exp1, expanded) := expand(exp1);

          if expanded then
            outExp := expandBinaryPowMatrix2(exp1, n);
          end if;
        then
          (outExp, expanded);

      // a ^ n where n is unknown, subscript the whole expression.
      else expandGeneric(exp, resize);
    end match;
  end expandBinaryPowMatrix;

  function expandBinaryPowMatrix2
    input Expression matrix;
    input Integer n;
    output Expression exp;
  algorithm
    exp := match n
      // A^1 = A
      case 1 then matrix;
      // A^2 = A * A
      case 2 then makeBinaryMatrixProduct(matrix, matrix);

      // A^n = A^m * A^m where n = 2*m
      case _ guard intMod(n, 2) == 0
        algorithm
          exp := expandBinaryPowMatrix2(matrix, intDiv(n, 2));
        then
          makeBinaryMatrixProduct(exp, exp);

      // A^n = A * A^(n-1)
      else
        algorithm
          exp := expandBinaryPowMatrix2(matrix, n - 1);
        then
          makeBinaryMatrixProduct(matrix, exp);

    end match;
  end expandBinaryPowMatrix2;

  function expandUnary
    input Expression exp;
    output Expression outExp;
    output Boolean expanded;
  protected
    Expression operand;
    Operator op, scalar_op;
  algorithm
    Expression.UNARY(op, operand) := exp;
    (operand, expanded) := expand(operand);

    if expanded then
      scalar_op := Operator.scalarize(op);
      outExp := Expression.mapArrayElements(operand,
        function SimplifyExp.simplifyUnaryOp(op = scalar_op));
    else
      outExp := exp;
    end if;
  end expandUnary;

  function expandLogicalBinary
    input Expression exp;
    output Expression outExp;
    output Boolean expanded;
  protected
    Expression exp1, exp2;
    Operator op;
  algorithm
    Expression.LBINARY(exp1 = exp1, operator = op, exp2 = exp2) := exp;

    if Type.isArray(Operator.typeOf(op)) then
      (exp1, expanded) := expand(exp1);

      if expanded then
        (exp2, expanded) := expand(exp2);
      end if;

      if expanded then
        outExp := expandBinaryElementWise2(exp1, op, exp2, makeLBinaryOp);
      else
        outExp := exp;
      end if;
    else
      outExp := exp;
      expanded := true;
    end if;
  end expandLogicalBinary;

  function makeLBinaryOp
    input Expression exp1;
    input Operator op;
    input Expression exp2;
    output Expression exp;
  algorithm
    if Expression.isScalarLiteral(exp1) and Expression.isScalarLiteral(exp2) then
      exp := Ceval.evalLogicBinaryOp(exp1, op, exp2);
    else
      exp := Expression.LBINARY(exp1, op, exp2);
    end if;
  end makeLBinaryOp;

  function expandLogicalUnary
    input Expression exp;
    output Expression outExp;
    output Boolean expanded;
  protected
    Expression operand;
    Operator op, scalar_op;
  algorithm
    Expression.LUNARY(op, operand) := exp;
    (operand, expanded) := expand(operand);

    if expanded then
      scalar_op := Operator.scalarize(op);
      outExp := Expression.mapArrayElements(operand, function makeLogicalUnaryOp(op = scalar_op));
    else
      outExp := exp;
    end if;
  end expandLogicalUnary;

  function makeLogicalUnaryOp
    input Expression exp1;
    input Operator op;
    output Expression exp = Expression.LUNARY(op, exp1);
  end makeLogicalUnaryOp;

  function expandCast
    input Expression castExp;
    output Expression outExp;
    output Boolean expanded;
  protected
    Expression exp;
    Type ty;
  algorithm
    Expression.CAST(exp = exp, ty = ty) := castExp;
    (outExp, expanded) := expand(exp);

    if expanded and not referenceEq(exp, outExp) then
      outExp := Expression.typeCast(outExp, ty);
    else
      outExp := castExp;
    end if;
  end expandCast;

  function expandGeneric
    input Expression exp;
    input Boolean resize;
    output Expression outExp;
    output Boolean expanded;
  protected
    Type ty;
    list<Dimension> dims;
    list<list<Subscript>> subs;
  algorithm
    ty := Expression.typeOf(exp);

    if Type.isArray(ty) then
      expanded := Type.hasKnownSize(ty);

      if expanded then
        dims := Type.arrayDims(ty);
        subs := list(list(Subscript.INDEX(e) for e in RangeIterator.toList(RangeIterator.fromDim(d, resize))) for d in dims);
        outExp := expandGeneric2(subs, exp, ty);
      else
        outExp := exp;
      end if;
    else
      outExp := exp;
      expanded := true;
    end if;
  end expandGeneric;

  function expandGeneric2
    input list<list<Subscript>> subs;
    input Expression exp;
    input Type ty;
    input list<Subscript> accum = {};
    output Expression outExp;
  protected
    Type t;
    list<Subscript> sub;
    array<Expression> expl;
    list<list<Subscript>> rest_subs;
    Integer i;
  algorithm
    outExp := match subs
      case sub :: rest_subs
        algorithm
          t := Type.unliftArray(ty);
          expl := arrayCreateNoInit(listLength(sub), exp);
          i := 1;

          for s in sub loop
            arrayUpdateNoBoundsChecking(expl, i,
              expandGeneric2(rest_subs, exp, t, s :: accum));
            i := i + 1;
          end for;
        then
          Expression.makeArray(ty, expl);

      case {}
        algorithm
          outExp := exp;
          for s in listReverse(accum) loop
            outExp := Expression.applySubscript(s, outExp);
          end for;
        then
          outExp;

    end match;
  end expandGeneric2;

  function expandCallArgs
    input output Expression exp;
  protected
    Call call;
  algorithm
    () := match exp
      case Expression.CALL(call = call as Call.TYPED_CALL())
        algorithm
          call.arguments := list(expand(arg) for arg in call.arguments);
          exp.call := call;
        then
          ();

      else ();
    end match;
  end expandCallArgs;

annotation(__OpenModelica_Interface="frontend");
end NFExpandExp;
