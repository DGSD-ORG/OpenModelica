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

encapsulated package NFInstNode

import BaseModelica;
import Binding = NFBinding;
import Component = NFComponent;
import Class = NFClass;
import SCode;
import Absyn;
import AbsynUtil;
import Type = NFType;
import NFFunction.Function;
import Sections = NFSections;
import Pointer;
import Error;
import Prefixes = NFPrefixes;
import Visibility = NFPrefixes.Visibility;
import AccessLevel = NFPrefixes.AccessLevel;
import NFModifier.Modifier;
import SCodeDump;
import DAE;
import Expression = NFExpression;

protected
import List;
import ConvertDAE = NFConvertDAE;
import Restriction = NFRestriction;
import NFClassTree.ClassTree;
import SCodeUtil;
import IOStream;
import Variable = NFVariable;
import UnorderedMap;

public
uniontype InstNodeType
  record NORMAL_CLASS
    "An element with no specific characteristics."
  end NORMAL_CLASS;

  record BASE_CLASS
    "A base class extended by another class."
    InstNode parent;
    SCode.Element definition "The extends clause definition.";
    InstNodeType ty "The original node type before the class was extended.";
  end BASE_CLASS;

  record DERIVED_CLASS
    "A short class definition."
    InstNodeType ty "The base node type not considering that it's a derived class.";
  end DERIVED_CLASS;

  record BUILTIN_CLASS
    "A builtin element."
  end BUILTIN_CLASS;

  record TOP_SCOPE
    "The unnamed class containing all the top-level classes."
    InstNode annotationScope;
    UnorderedMap<String, InstNode> generatedInners;
  end TOP_SCOPE;

  record ROOT_CLASS
    "The root of the instance tree, i.e. the class that the instantiation starts from."
    InstNode parent "The parent of the class, e.g. when instantiating a function
                     in a component where the component is the parent.";
  end ROOT_CLASS;

  record NORMAL_COMP
  end NORMAL_COMP;

  record REDECLARED_COMP
    InstNode parent "The parent of the replaced component";
  end REDECLARED_COMP;

  record REDECLARED_CLASS
    InstNode parent;
    InstNodeType originalType;
    Option<InstNode> originalNode;
  end REDECLARED_CLASS;

  record GENERATED_INNER
    "A generated inner element due to a missing outer."
  end GENERATED_INNER;

  record IMPLICIT_SCOPE
    "An implicit scope that's ignored when e.g. constructing a scope path. Not
     used by implicit scope nodes since those have no node type (they're
     implicitly implicit), but by e.g. the annotation scope."
  end IMPLICIT_SCOPE;
end InstNodeType;

constant Integer NUMBER_OF_CACHES = 2;

type PackageCacheState = enumeration(
  NOT_INITIALIZED,
  PROCESSING,
  EXPANDED,
  PARTIALLY_INSTANTIATED,
  INSTANTIATED
);

uniontype CachedData

  record NO_CACHE end NO_CACHE;

  record PACKAGE
    InstNode instance;
    PackageCacheState state;
  end PACKAGE;

  record FUNCTION
    list<Function> funcs;
    Boolean typed;
    Boolean specialBuiltin;
  end FUNCTION;

  function empty
    output array<CachedData> cache = arrayCreate(NUMBER_OF_CACHES, NO_CACHE());
  end empty;

  function initFunc
    input array<CachedData> caches;
  protected
    CachedData func_cache;
  algorithm
    func_cache := getFuncCache(caches);
    func_cache := match func_cache
      case NO_CACHE() then FUNCTION({}, false, false);
      case FUNCTION() then func_cache;
    end match;

    setFuncCache(caches, func_cache);
  end initFunc;

  function addFunc
    input Function fn;
    input Boolean specialBuiltin;
    input array<CachedData> caches;
  protected
    CachedData func_cache;
  algorithm
    func_cache := getFuncCache(caches);
    func_cache := match func_cache
      case NO_CACHE() then FUNCTION({fn}, false, specialBuiltin);
      // Append to end so the error messages are ordered properly.
      case FUNCTION() then FUNCTION(listAppend(func_cache.funcs,{fn}), false,
                                    func_cache.specialBuiltin or specialBuiltin);
      else
        algorithm
          Error.assertion(false, getInstanceName() + ": Invalid cache for function", sourceInfo());
        then
          fail();
    end match;

    setFuncCache(caches, func_cache);
  end addFunc;

  function getFuncCache
    input array<CachedData> in_caches;
    output CachedData out_cache = arrayGet(in_caches, 1);
  end getFuncCache;

  function setFuncCache
    input array<CachedData> in_caches;
    input CachedData in_cache;
    algorithm
      arrayUpdate(in_caches, 1, in_cache);
  end setFuncCache;

  function getPackageCache
    input array<CachedData> in_caches;
    output CachedData out_cache = arrayGet(in_caches, 2);
  end getPackageCache;

  function setPackageCache
    input array<CachedData> in_caches;
    input CachedData in_cache;
    output array<CachedData> out_caches = arrayUpdate(in_caches, 2, in_cache);
  end setPackageCache;

  function clearPackageCache
    input array<CachedData> in_caches;
    output array<CachedData> out_caches = arrayUpdate(in_caches, 2, NO_CACHE());
  end clearPackageCache;
end CachedData;

uniontype InstNode
  record CLASS_NODE
    String name;
    SCode.Element definition;
    Visibility visibility;
    Pointer<Class> cls;
    array<CachedData> caches;
    InstNode parentScope;
    InstNodeType nodeType;
  end CLASS_NODE;

  record COMPONENT_NODE
    String name;
    Option<SCode.Element> definition;
    Visibility visibility;
    Pointer<Component> component;
    InstNode parent "The instance that this component is part of.";
    InstNodeType nodeType;
  end COMPONENT_NODE;

  record INNER_OUTER_NODE
    "A node representing an outer element, with a reference to the corresponding inner."
    InstNode innerNode;
    InstNode outerNode;
  end INNER_OUTER_NODE;

  record REF_NODE
    Integer index;
  end REF_NODE;

  record NAME_NODE
    String name;
  end NAME_NODE;

  record IMPLICIT_SCOPE
    InstNode parentScope;
    list<InstNode> locals;
  end IMPLICIT_SCOPE;

  record ITERATOR_NODE
    Expression exp;
  end ITERATOR_NODE;

  record VAR_NODE
    "This is an extension for better use in the backend. Not used in the Frontend.
    NOTE: Map and traversal functions are not allowed to follow the variable
    pointer, it would create cyclic behaviour! Var->cref->pointer->Var"
    String name;
    Pointer<Variable> varPointer;
  end VAR_NODE;

  record EMPTY_NODE end EMPTY_NODE;

  function new
    input SCode.Element definition;
    input InstNode parent;
    output InstNode node;
  algorithm
    node := match definition
      case SCode.CLASS() then newClass(definition, parent);
      case SCode.COMPONENT() then newComponent(definition, parent);
    end match;
  end new;

  function newClass
    input SCode.Element definition;
    input InstNode parent;
    input InstNodeType nodeType = NORMAL_CLASS();
    output InstNode node;
  protected
    String name;
    SCode.Visibility vis;
  algorithm
    SCode.CLASS(name = name, prefixes = SCode.PREFIXES(visibility = vis)) := definition;
    node := CLASS_NODE(name, definition, Prefixes.visibilityFromSCode(vis),
      Pointer.create(Class.NOT_INSTANTIATED()), CachedData.empty(), parent, nodeType);
  end newClass;

  function newComponent
    input SCode.Element definition;
    input InstNode parent = EMPTY_NODE();
    output InstNode node;
  protected
    String name;
    SCode.Visibility vis;
  algorithm
    SCode.COMPONENT(name = name, prefixes = SCode.PREFIXES(visibility = vis)) := definition;
    node := COMPONENT_NODE(name, SOME(definition), Prefixes.visibilityFromSCode(vis),
      Pointer.create(Component.new(definition)), parent, InstNodeType.NORMAL_COMP());
  end newComponent;

  function newExtends
    input SCode.Element definition;
    input InstNode parent;
    output InstNode node;
  protected
    Absyn.Path base_path;
    String name;
    SCode.Visibility vis;
  algorithm
    SCode.Element.EXTENDS(baseClassPath = base_path, visibility = vis) := definition;
    name := AbsynUtil.pathLastIdent(base_path);
    node := CLASS_NODE(name, definition, Prefixes.visibilityFromSCode(vis),
      Pointer.create(Class.NOT_INSTANTIATED()), CachedData.empty(), parent,
      InstNodeType.BASE_CLASS(parent, definition, nodeType(parent)));
  end newExtends;

  function newIterator
    input String name;
    input Type ty;
    input SourceInfo info;
    output InstNode iterator;
  algorithm
    iterator := fromComponent(name, Component.newIterator(ty, info), EMPTY_NODE());
  end newIterator;

  function newIndexedIterator
    input Integer index;
    input String name = "i";
    input SourceInfo info = AbsynUtil.dummyInfo;
    input Type ty = Type.INTEGER();
    output InstNode iterator;
  algorithm
    iterator := newIterator("$" + name + String(index), ty, info);
  end newIndexedIterator;

  function fromComponent
    input String name;
    input Component component;
    input InstNode parent;
    output InstNode node;
  algorithm
    node := COMPONENT_NODE(name, NONE(), Visibility.PUBLIC, Pointer.create(component),
                           parent, InstNodeType.NORMAL_COMP());
  end fromComponent;

  function isClass
    input InstNode node;
    output Boolean isClass;
  algorithm
    isClass := match node
      case CLASS_NODE() then true;
      case INNER_OUTER_NODE() then isClass(node.innerNode);
      else false;
    end match;
  end isClass;

  function isBaseClass
    input InstNode node;
    output Boolean isBaseClass;
  algorithm
    isBaseClass := match node
      case CLASS_NODE(nodeType = InstNodeType.BASE_CLASS()) then true;
      else false;
    end match;
  end isBaseClass;

  function isUserdefinedClass
    input InstNode node;
    output Boolean isUserdefined;
  protected
    InstNodeType ty;
  algorithm
    isUserdefined := match node
      case CLASS_NODE(nodeType = ty)
        then match ty
          case InstNodeType.NORMAL_CLASS() then true;
          case InstNodeType.BASE_CLASS() then true;
          case InstNodeType.DERIVED_CLASS() then true;
          case InstNodeType.REDECLARED_CLASS() then isUserdefinedClass(ty.parent);
          else false;
        end match;
      else false;
    end match;
  end isUserdefinedClass;

  function isDerivedClass
    input InstNode node;
    output Boolean isDerived;
  algorithm
    isDerived := match node
      case CLASS_NODE(nodeType = InstNodeType.DERIVED_CLASS()) then true;
      else false;
    end match;
  end isDerivedClass;

  function isRootClass
    input InstNode node;
    output Boolean res;
  algorithm
    res := match node
      case CLASS_NODE(nodeType = InstNodeType.ROOT_CLASS()) then true;
      else false;
    end match;
  end isRootClass;

  function isFunction
    input InstNode node;
    output Boolean isFunc;
  algorithm
    isFunc := match node
      case CLASS_NODE() then Class.isFunction(Pointer.access(node.cls));
      else false;
    end match;
  end isFunction;

  function isComponent
    input InstNode node;
    output Boolean isComponent;
  algorithm
    isComponent := match node
      case COMPONENT_NODE() then true;
      case INNER_OUTER_NODE() then isComponent(node.innerNode);
      else false;
    end match;
  end isComponent;

  function isRef
    input InstNode node;
    output Boolean isRef;
  algorithm
    isRef := match node
      case REF_NODE() then true;
      else false;
    end match;
  end isRef;

  function isEmpty
    input InstNode node;
    output Boolean isEmpty;
  algorithm
    isEmpty := match node
      case EMPTY_NODE() then true;
      else false;
    end match;
  end isEmpty;

  function isImplicit
    input InstNode node;
    output Boolean isImplicit;
  algorithm
    isImplicit := match node
      case IMPLICIT_SCOPE() then true;
      else false;
    end match;
  end isImplicit;

  function isName
    input InstNode node;
    output Boolean isName;
  algorithm
    isName := match node
      case NAME_NODE() then true;
      else false;
    end match;
  end isName;

  function isConnector
    input InstNode node;
    output Boolean isConnector;
  algorithm
    isConnector := match node
      case COMPONENT_NODE() then Component.isConnector(component(node));
      case NAME_NODE() then true;
      else false;
    end match;
  end isConnector;

  function isExpandableConnector
    input InstNode node;
    output Boolean isConnector;
  algorithm
    isConnector := match node
      case COMPONENT_NODE() then Component.isExpandableConnector(component(node));
      else false;
    end match;
  end isExpandableConnector;

  function hasParentExpandableConnector
  "@author: adrpo
   returns true if itself or any of the parents are expandable connectors"
    input InstNode node;
    output Boolean b = isExpandableConnector(node);
  protected
    InstNode p;
  algorithm
    p := node;
    while not isEmpty(p) loop
      p := parent(p);
      b := boolOr(b, isExpandableConnector(p));
      if b then
        break;
      end if;
    end while;
  end hasParentExpandableConnector;

  function isOperator
    input InstNode node;
    output Boolean op;
  algorithm
    op := match node
      case CLASS_NODE() then SCodeUtil.isOperator(node.definition);
      case INNER_OUTER_NODE() then isOperator(node.innerNode);
      else false;
    end match;
  end isOperator;

  function name
    input InstNode node;
    output String name;
  algorithm
    name := match node
      case CLASS_NODE() then node.name;
      case COMPONENT_NODE() then node.name;
      case INNER_OUTER_NODE() then name(node.innerNode);
      case VAR_NODE() then node.name;
      // For bug catching, these names should never be used.
      case REF_NODE() then "$REF[" + String(node.index) + "]";
      case NAME_NODE() then node.name;
      case IMPLICIT_SCOPE() then "$IMPLICIT";
      case ITERATOR_NODE() then "$ITERATOR(" + Expression.toString(node.exp) + ")";
      case EMPTY_NODE() then "$EMPTY";
    end match;
  end name;

  function isNamed
    input InstNode node;
    input String name;
    output Boolean res;
  algorithm
    res := match node
      case CLASS_NODE() then node.name == name;
      case COMPONENT_NODE() then node.name == name;
      case INNER_OUTER_NODE() then isNamed(node.innerNode, name);
      case VAR_NODE() then node.name == name;
      case NAME_NODE() then node.name == name;
      else false;
    end match;
  end isNamed;

  function className
    input InstNode node;
    output String name;
  algorithm
    CLASS_NODE(name = name) := node;
  end className;

  function scopeName
    "Returns the name of a scope, which in the case of a component is the name
     of the component's type, and for a class simply the name of the class."
    input InstNode node;
    output String outName = name(classScope(explicitScope(node)));
  end scopeName;

  function typeName
    "Returns the type of node the given node is as a string."
    input InstNode node;
    output String name;
  algorithm
    name := match node
      case CLASS_NODE()         then "class";
      case COMPONENT_NODE()     then "component";
      case INNER_OUTER_NODE()   then typeName(node.innerNode);
      case REF_NODE()           then "ref node";
      case NAME_NODE()          then "name node";
      case IMPLICIT_SCOPE()     then "implicit scope";
      case EMPTY_NODE()         then "empty node";
      case VAR_NODE()           then "var node";
    end match;
  end typeName;

  function rename
    input String name;
    input output InstNode node;
  algorithm
    () := match node
      case CLASS_NODE()
        algorithm
          node.name := name;
        then
          ();

      case COMPONENT_NODE()
        algorithm
          node.name := name;
        then
          ();

      case NAME_NODE()
        algorithm
          node.name := name;
        then
          ();

      case VAR_NODE()
        algorithm
          node.name := name;
        then
          ();
    end match;
  end rename;

  function parent
    input InstNode node;
    output InstNode parent;
  algorithm
    parent := match node
      case CLASS_NODE() then node.parentScope;
      case COMPONENT_NODE() then node.parent;
      case IMPLICIT_SCOPE() then node.parentScope;
      else EMPTY_NODE();
    end match;
  end parent;

  function explicitParent
    input InstNode node;
    output InstNode parentNode = explicitScope(parent(node));
  end explicitParent;

  function classParent
    input InstNode node;
    output InstNode parent;
  algorithm
    CLASS_NODE(parentScope = parent) := node;
  end classParent;

  function instanceParent
    "Returns the parent of the node in the instance tree."
    input InstNode node;
    output InstNode parent;
  algorithm
    parent := match node
      case CLASS_NODE() then getDerivedNode(parent(getDerivedNode(node)));
      case COMPONENT_NODE(nodeType = InstNodeType.REDECLARED_COMP(parent = parent))
        then getDerivedNode(parent);
      case COMPONENT_NODE() then getDerivedNode(parent(getDerivedNode(node)));
      case IMPLICIT_SCOPE() then getDerivedNode(parent(getDerivedNode(node)));
      else EMPTY_NODE();
    end match;
  end instanceParent;

  function rootParent
    input InstNode node;
    output InstNode parent;
  algorithm
    parent := match node
      case CLASS_NODE() then rootTypeParent(node.nodeType, node);
      else parent(node);
    end match;
  end rootParent;

  function rootTypeParent
    input InstNodeType nodeType;
    input InstNode node;
    output InstNode parent;
  algorithm
    parent := match nodeType
      case InstNodeType.ROOT_CLASS() guard not isEmpty(nodeType.parent) then nodeType.parent;
      case InstNodeType.DERIVED_CLASS() then rootTypeParent(nodeType.ty, node);
      else parent(node);
    end match;
  end rootTypeParent;

  function parentScope
    "Returns the parent scope of a node. In the case of a class this is simply
     the enclosing class. In the case of a component it is the enclosing class of
     the component's type."
    input InstNode node;
    input Boolean ignoreRedeclare = false;
    output InstNode scope;
  protected
    InstNode orig_node;
  algorithm
    scope := match node
      case CLASS_NODE(nodeType = InstNodeType.DERIVED_CLASS())
        algorithm
          scope := Class.lastBaseClass(node);
        then
          if isBuiltin(scope) then
            // Builtin types like Real do not have a parent set, go to the top scope instead.
            topScope(node.parentScope)
          elseif referenceEq(node, scope) then
            // lastBaseClass above might return the same node if the class has
            // been flattened, go directly to the parent to avoid an infinite loop.
            node.parentScope
          else
            parentScope(scope);

      case CLASS_NODE(nodeType = InstNodeType.REDECLARED_CLASS(originalNode = SOME(orig_node)))
        guard ignoreRedeclare
        then parentScope(orig_node);

      case CLASS_NODE(nodeType = InstNodeType.REDECLARED_CLASS(parent = scope))
        guard ignoreRedeclare
        then scope;

      case CLASS_NODE() then node.parentScope;
      case COMPONENT_NODE() then parentScope(Component.classInstance(Pointer.access(node.component)));
      case IMPLICIT_SCOPE() then node.parentScope;
    end match;
  end parentScope;

  function enclosingScopePath
    "Returns the enclosing scopes of a node as a path."
    input InstNode node;
    input Boolean ignoreRedeclare = false;
    output Absyn.Path path;
  algorithm
    path := AbsynUtil.stringListPath(
      list(InstNode.name(n) for n in enclosingScopeList(node, ignoreRedeclare)));
  end enclosingScopePath;

  function enclosingScopeList
    "Returns the enclosing scopes of a node as a list of nodes."
    input InstNode node;
    input Boolean ignoreRedeclare = false;
    output list<InstNode> res = {};
  protected
    InstNode scope = node;
  algorithm
    while not isTopScope(scope) loop
      res := scope :: res;
      scope := classScope(parentScope(scope, ignoreRedeclare));
    end while;
  end enclosingScopeList;

  function classScope
    input InstNode node;
    output InstNode scope;
  algorithm
    scope := match node
      case COMPONENT_NODE()
        then Component.classInstance(Pointer.access(node.component));
      else node;
    end match;
  end classScope;

  function libraryScope
    "Returns the top-level class the given node belongs to."
    input InstNode node;
    output InstNode lib;
  algorithm
    lib := match node
      case CLASS_NODE(parentScope = CLASS_NODE(nodeType = InstNodeType.TOP_SCOPE())) then node;
      else libraryScope(parentScope(node));
    end match;
  end libraryScope;

  function topScope
    input InstNode node;
    output InstNode topScope;
  algorithm
    topScope := match node
      case CLASS_NODE(nodeType = InstNodeType.TOP_SCOPE()) then node;
      else topScope(parent(node));
    end match;
  end topScope;

  function annotationScope
    input InstNode node;
    output InstNode annScope;
  algorithm
    annScope := match node
      case CLASS_NODE(nodeType = InstNodeType.TOP_SCOPE(annotationScope = annScope)) then annScope;
      else annotationScope(parentScope(node));
    end match;
  end annotationScope;

  function isTopScope
    input InstNode node;
    output Boolean res;
  algorithm
    res := match node
      case CLASS_NODE(nodeType = InstNodeType.TOP_SCOPE()) then true;
      else false;
    end match;
  end isTopScope;

  function topComponent
    input InstNode node;
    output InstNode topComponent;
  algorithm
    topComponent := match node
      case COMPONENT_NODE(parent = EMPTY_NODE()) then node;
      case COMPONENT_NODE() then topComponent(node.parent);
    end match;
  end topComponent;

  function setParent
    input InstNode parent;
    input output InstNode node;
  algorithm
    () := match node
      case CLASS_NODE()
        algorithm
          node.parentScope := parent;
        then
          ();

      case COMPONENT_NODE()
        algorithm
          node.parent := parent;
        then
          ();

      case IMPLICIT_SCOPE()
        algorithm
          node.parentScope := parent;
        then
          ();
    end match;
  end setParent;

  function setOrphanParent
    "Sets the parent of a node if the node lacks a parent, otherwise does nothing."
    input InstNode parent;
    input output InstNode node;
  algorithm
    () := match node
      case CLASS_NODE(parentScope = EMPTY_NODE())
        algorithm
          node.parentScope := parent;
        then
          ();

      case COMPONENT_NODE(parent = EMPTY_NODE())
        algorithm
          node.parent := parent;
        then
          ();

      else ();
    end match;
  end setOrphanParent;

  function getClass
    input InstNode node;
    output Class cls;
  algorithm
    cls := match node
      case CLASS_NODE() then Pointer.access(node.cls);
      case COMPONENT_NODE()
        then getClass(Component.classInstance(Pointer.access(node.component)));
    end match;
  end getClass;

  function getDerivedClass
    input InstNode node;
    output Class cls;
  algorithm
    cls := match node
      case CLASS_NODE() then getClass(getDerivedNode(node));
      case COMPONENT_NODE()
        then getClass(getDerivedNode(Component.classInstance(Pointer.access(node.component))));
    end match;
  end getDerivedClass;

  function getDerivedNode
    input InstNode node;
    input Boolean recursive = true;
    output InstNode derived;
  algorithm
    derived := match node
      case CLASS_NODE() then getDerivedNode2(node, node.nodeType, recursive);
      else node;
    end match;
  end getDerivedNode;

  function getDerivedNode2
    input InstNode node;
    input InstNodeType ty;
    input Boolean recursive;
    output InstNode derived;
  algorithm
    derived := match ty
      case InstNodeType.BASE_CLASS() then if recursive then getDerivedNode(ty.parent) else ty.parent;
      case InstNodeType.DERIVED_CLASS() then getDerivedNode2(node, ty.ty, recursive);
      else node;
    end match;
  end getDerivedNode2;

  function updateClass
    input Class cls;
    input output InstNode node;
  algorithm
    node := match node
      case CLASS_NODE()
        algorithm
          Pointer.update(node.cls, cls);
        then
          node;
    end match;
  end updateClass;

  function component
    input InstNode node;
    output Component component;
  algorithm
    component := match node
      case COMPONENT_NODE() then Pointer.access(node.component);
      case VAR_NODE()       then Component.WILD();
      case NAME_NODE()      then Component.WILD();
    end match;
  end component;

  function updateComponent
    input Component component;
    input output InstNode node;
  algorithm
    node := match node
      case COMPONENT_NODE()
        algorithm
          Pointer.update(node.component, component);
        then
          node;
    end match;
  end updateComponent;

  function replaceComponent
    input Component component;
    input output InstNode node;
  algorithm
    () := match node
      case COMPONENT_NODE()
        algorithm
          node.component := Pointer.create(component);
        then
          ();
    end match;
  end replaceComponent;

  function replaceClass
    input Class cls;
    input output InstNode node;
  algorithm
    () := match node
      case CLASS_NODE()
        algorithm
          node.cls := Pointer.create(cls);
        then
          ();
    end match;
  end replaceClass;

  function nodeType
    input InstNode node;
    output InstNodeType nodeType;
  algorithm
    nodeType := match node
      case CLASS_NODE() then node.nodeType;
      case COMPONENT_NODE() then node.nodeType;
    end match;
  end nodeType;

  function derivedNodeType
    input InstNode node;
    output InstNodeType ty;
  algorithm
    ty := match node
      case CLASS_NODE(nodeType = InstNodeType.DERIVED_CLASS(ty = ty)) then ty;
      else nodeType(node);
    end match;
  end derivedNodeType;

  function setNodeType
    input InstNodeType nodeType;
    input output InstNode node;
  algorithm
    () := match node
      case CLASS_NODE()
        algorithm
          node.nodeType := nodeType;
        then
          ();

      case COMPONENT_NODE()
        algorithm
          node.nodeType := nodeType;
        then
          ();

      else ();
    end match;
  end setNodeType;

  function definition
    input InstNode node;
    output SCode.Element definition;
  algorithm
    definition := match node
      case CLASS_NODE() then node.definition;
      case COMPONENT_NODE(definition = SOME(definition)) then definition;
    end match;
  end definition;

  function extendsDefinition
    input InstNode node;
    output SCode.Element definition;
  algorithm
    InstNodeType.BASE_CLASS(definition = definition) := derivedNodeType(node);
  end extendsDefinition;

  function setDefinition
    input SCode.Element definition;
    input output InstNode node;
  algorithm
    () := match node
      case CLASS_NODE()
        algorithm
          node.definition := definition;
        then
          ();

      case COMPONENT_NODE()
        algorithm
          node.definition := SOME(definition);
        then
          ();

    end match;
  end setDefinition;

  function setComponentDirection
    "creates new component!"
    input Prefixes.Direction direction;
    input output InstNode node;
  algorithm
    node := match node
      case COMPONENT_NODE() algorithm
        node.component := Pointer.create(Component.setDirection(direction, Pointer.access(node.component)));
      then node;

      else algorithm
        Error.addMessage(Error.INTERNAL_ERROR,{getInstanceName() + " failed for non component node: " + toString(node)});
      then fail();
    end match;
  end setComponentDirection;

  function info
    input InstNode node;
    output SourceInfo info;
  algorithm
    info := matchcontinue node
      local
        InstNodeType ty;
      case CLASS_NODE(nodeType = ty as InstNodeType.BASE_CLASS())
        then SCodeUtil.elementInfo(ty.definition);
      case CLASS_NODE() then SCodeUtil.elementInfo(node.definition);
      case COMPONENT_NODE() then Component.info(Pointer.access(node.component));
      case COMPONENT_NODE() then info(node.parent);
      else AbsynUtil.dummyInfo;
    end matchcontinue;
  end info;

  function getType
    input InstNode node;
    output Type ty;
  protected
    Variable var;
  algorithm
    ty := match node
      case CLASS_NODE()     then Class.getType(Pointer.access(node.cls), node);
      case COMPONENT_NODE() then Component.getType(Pointer.access(node.component));
      case VAR_NODE() algorithm
        var := Pointer.access(node.varPointer);
      then var.ty;
    end match;
  end getType;

  function classApply<ArgT>
    input output InstNode node;
    input FuncType func;
    input ArgT arg;

    partial function FuncType
      input ArgT arg;
      input output Class cls;
    end FuncType;
  algorithm
    () := match node
      case CLASS_NODE()
        algorithm
          Pointer.update(node.cls, func(arg, Pointer.access(node.cls)));
        then
          ();
    end match;
  end classApply;

  function componentApply<ArgT>
    input output InstNode node;
    input FuncType func;
    input ArgT arg;

    partial function FuncType
      input ArgT arg;
      input output Component node;
    end FuncType;
  algorithm
    () := match node
      case COMPONENT_NODE()
        algorithm
          Pointer.update(node.component, func(arg, Pointer.access(node.component)));
        then
          ();
    end match;
  end componentApply;

  function scopeList
    input InstNode node;
    input Boolean includeRoot = false "Whether to include the root class name or not.";
    input list<InstNode> accumScopes = {};
    output list<InstNode> scopes;
  algorithm
    scopes := match node
      local
        InstNode parent;

      case CLASS_NODE() then scopeListClass(node, node.nodeType, includeRoot, accumScopes);
      case COMPONENT_NODE(parent = EMPTY_NODE()) then accumScopes;
      case COMPONENT_NODE(nodeType = InstNodeType.REDECLARED_COMP(parent = parent))
        then scopeList(parent, includeRoot, node :: accumScopes);
      case COMPONENT_NODE() then scopeList(node.parent, includeRoot, node :: accumScopes);
      case IMPLICIT_SCOPE() then scopeList(node.parentScope, includeRoot, accumScopes);
      else accumScopes;
    end match;
  end scopeList;

  function scopeListClass
    input InstNode clsNode;
    input InstNodeType ty;
    input Boolean includeRoot;
    input list<InstNode> accumScopes = {};
    output list<InstNode> scopes;
  algorithm
    scopes := match ty
      case InstNodeType.NORMAL_CLASS()
        then scopeList(parent(clsNode), includeRoot, clsNode :: accumScopes);
      case InstNodeType.BASE_CLASS()
        then scopeList(ty.parent, includeRoot, accumScopes);
      case InstNodeType.DERIVED_CLASS()
        then scopeListClass(clsNode, ty.ty, includeRoot, accumScopes);
      case InstNodeType.BUILTIN_CLASS()
        then clsNode :: accumScopes;
      case InstNodeType.TOP_SCOPE()
        then accumScopes;
      case InstNodeType.ROOT_CLASS()
        then if includeRoot then
            scopeList(parent(clsNode), includeRoot, clsNode :: accumScopes)
          else
            accumScopes;
      case InstNodeType.REDECLARED_CLASS()
        then scopeList(ty.parent, includeRoot, getDerivedNode(clsNode) :: accumScopes);
      case InstNodeType.IMPLICIT_SCOPE()
        then scopeList(parent(clsNode), includeRoot, accumScopes);
      else
        algorithm
          Error.assertion(false, getInstanceName() + " got unknown node type", sourceInfo());
        then
          fail();
    end match;
  end scopeListClass;

  function getAnnotation
    input String name;
    input InstNode node;
    output SCode.Mod mod;
    output InstNode scope = node;
  protected
    Option<SCode.Annotation> ann;
  algorithm
    while InstNode.isComponent(scope) loop
      ann := SCodeUtil.commentAnnotation(Component.comment(InstNode.component(scope)));

      if isSome(ann) then
        mod := SCodeUtil.lookupAnnotation(Util.getOption(ann), name);

        if not SCodeUtil.isEmptyMod(mod) then
          scope := instanceParent(scope);
          return;
        end if;
      end if;

      scope := instanceParent(scope);
    end while;

    mod := SCode.Mod.NOMOD();
  end getAnnotation;

  type ScopeType = enumeration(
    RELATIVE       "Stops at a root class and doesn't include the root",
    INCLUDING_ROOT "Stops at a root class and includes the root",
    FULL           "Stops at the top scope"
  );

  function rootPath
    input InstNode node;
    input Boolean ignoreBaseClass = false "Ignore that a class is a base class if true.";
    output Absyn.Path path = scopePath(node, ScopeType.INCLUDING_ROOT, ignoreBaseClass);
  end rootPath;

  function fullPath
    input InstNode node;
    input Boolean ignoreBaseClass = false "Ignore that a class is a base class if true.";
    output Absyn.Path path = scopePath(node, ScopeType.FULL, ignoreBaseClass);
  end fullPath;

  function scopePath
    input InstNode node;
    input ScopeType scopeType = ScopeType.RELATIVE;
    input Boolean ignoreBaseClass = false "Ignore that a class is a base class if true.";
    output Absyn.Path path;
  algorithm
    path := match node
      local
        InstNodeType it;

      case CLASS_NODE(nodeType = it)
        then
          match it
            case InstNodeType.BASE_CLASS() guard not ignoreBaseClass then scopePath(it.parent, scopeType);
            else scopePath2(node.parentScope, scopeType, Absyn.IDENT(node.name));
          end match;

      case COMPONENT_NODE() then scopePath2(node.parent, scopeType, Absyn.IDENT(node.name));
      case IMPLICIT_SCOPE() then scopePath(node.parentScope, scopeType);

      // For debugging.
      else Absyn.IDENT(name(node));
    end match;
  end scopePath;

  function scopePath2
    input InstNode node;
    input ScopeType scopeType;
    input Absyn.Path accumPath;
    output Absyn.Path path;
  algorithm
    path := match node
      case CLASS_NODE() then scopePathClass(node, node.nodeType, scopeType, accumPath);
      case COMPONENT_NODE() then scopePath2(node.parent, scopeType, Absyn.QUALIFIED(node.name, accumPath));
      else accumPath;
    end match;
  end scopePath2;

  function scopePathClass
    input InstNode node;
    input InstNodeType ty;
    input ScopeType scopeType;
    input Absyn.Path accumPath;
    output Absyn.Path path;
  algorithm
    path := match ty
      case InstNodeType.NORMAL_CLASS()
        then scopePath2(classParent(node), scopeType, Absyn.QUALIFIED(className(node), accumPath));
      case InstNodeType.BASE_CLASS()
        then scopePath2(ty.parent, scopeType, accumPath);
      case InstNodeType.DERIVED_CLASS()
        then scopePathClass(node, ty.ty, scopeType, accumPath);
      case InstNodeType.BUILTIN_CLASS()
        then Absyn.QUALIFIED(className(node), accumPath);
      case InstNodeType.TOP_SCOPE()
        then accumPath;
      case InstNodeType.ROOT_CLASS()
        then if scopeType == ScopeType.FULL then
               scopePath2(classParent(node), scopeType, Absyn.QUALIFIED(className(node), accumPath))
             elseif scopeType == ScopeType.INCLUDING_ROOT then
               Absyn.QUALIFIED(className(node), accumPath)
             else
               accumPath;
      case InstNodeType.REDECLARED_CLASS()
        then scopePath2(ty.parent, scopeType, Absyn.QUALIFIED(className(node), accumPath));
      case InstNodeType.IMPLICIT_SCOPE()
        then scopePath2(classParent(node), scopeType, accumPath);
      else
        algorithm
          Error.assertion(false, getInstanceName() + " got unknown node type", sourceInfo());
        then
          fail();
    end match;
  end scopePathClass;

  function isInput
    input InstNode node;
    output Boolean isInput;
  algorithm
    isInput := match node
      case COMPONENT_NODE() then Component.isInput(Pointer.access(node.component));
      else false;
    end match;
  end isInput;

  function isOutput
    input InstNode node;
    output Boolean isOutput;
  algorithm
    isOutput := match node
      case COMPONENT_NODE() then Component.isOutput(Pointer.access(node.component));
      else false;
    end match;
  end isOutput;

  function isInner
    input InstNode node;
    output Boolean isInner;
  algorithm
    isInner := match node
      case COMPONENT_NODE() then Component.isInner(Pointer.access(node.component));
      case CLASS_NODE()
        then AbsynUtil.isInner(SCodeUtil.prefixesInnerOuter(SCodeUtil.elementPrefixes(node.definition)));
      case INNER_OUTER_NODE() then isInner(node.outerNode);
      else false;
    end match;
  end isInner;

  function isOuter
    input InstNode node;
    output Boolean isOuter;
  algorithm
    isOuter := match node
      case COMPONENT_NODE() then Component.isOuter(Pointer.access(node.component));
      case CLASS_NODE()
        then AbsynUtil.isOuter(SCodeUtil.prefixesInnerOuter(SCodeUtil.elementPrefixes(node.definition)));
      case INNER_OUTER_NODE() then isOuter(node.outerNode);
      else false;
    end match;
  end isOuter;

  function isOnlyOuter
    input InstNode node;
    output Boolean isOuter;
  algorithm
    isOuter := match node
      case COMPONENT_NODE() then Component.isOnlyOuter(Pointer.access(node.component));
      case CLASS_NODE()
        then AbsynUtil.isOnlyOuter(SCodeUtil.prefixesInnerOuter(SCodeUtil.elementPrefixes(node.definition)));
      case INNER_OUTER_NODE() then isOnlyOuter(node.outerNode);
      else false;
    end match;
  end isOnlyOuter;

  function isInnerOuterNode
    input InstNode node;
    output Boolean isIO;
  algorithm
    isIO := match node
      case INNER_OUTER_NODE() then true;
      else false;
    end match;
  end isInnerOuterNode;

  function isGeneratedInner
    input InstNode node;
    output Boolean isInner;
  algorithm
    isInner := match node
      case CLASS_NODE(nodeType = InstNodeType.GENERATED_INNER()) then true;
      case COMPONENT_NODE(nodeType = InstNodeType.GENERATED_INNER()) then true;
      else false;
    end match;
  end isGeneratedInner;

  function resolveInner
    input InstNode node;
    output InstNode innerNode;
  algorithm
    innerNode := match node
      case INNER_OUTER_NODE() then node.innerNode;
      else node;
    end match;
  end resolveInner;

  function resolveOuter
    input InstNode node;
    output InstNode outerNode;
  algorithm
    outerNode := match node
      case INNER_OUTER_NODE() then node.outerNode;
      else node;
    end match;
  end resolveOuter;

  function cacheInitFunc
    input output InstNode node;
  algorithm
    () := match node
      case CLASS_NODE() algorithm CachedData.initFunc(node.caches); then ();
      else algorithm Error.assertion(false, getInstanceName() + " got node without cache", sourceInfo()); then fail();
    end match;
  end cacheInitFunc;

  function cacheAddFunc
    input output InstNode node;
    input Function fn;
    input Boolean specialBuiltin;
  algorithm
    () := match node
      case CLASS_NODE() algorithm CachedData.addFunc(fn, specialBuiltin, node.caches); then ();
      else algorithm Error.assertion(false, getInstanceName() + " got node without cache", sourceInfo()); then fail();
    end match;
  end cacheAddFunc;

  function getFuncCache
    input InstNode inNode;
    output CachedData func_cache;
  algorithm
    func_cache := match inNode
      case CLASS_NODE() then CachedData.getFuncCache(inNode.caches);
      else algorithm Error.assertion(false, getInstanceName() + " got node without cache", sourceInfo()); then fail();
    end match;
  end getFuncCache;

  function setFuncCache
    input output InstNode node;
    input CachedData in_func_cache;
  algorithm
    () := match node
      case CLASS_NODE() algorithm CachedData.setFuncCache(node.caches, in_func_cache); then ();
      else algorithm Error.assertion(false, getInstanceName() + " got node without cache", sourceInfo()); then fail();
    end match;
  end setFuncCache;

  function getPackageCache
    input InstNode inNode;
    output CachedData pack_cache;
  algorithm
    pack_cache := match inNode
      case CLASS_NODE() then CachedData.getPackageCache(inNode.caches);
      else algorithm Error.assertion(false, getInstanceName() + " got node without cache", sourceInfo()); then fail();
    end match;
  end getPackageCache;

  function setPackageCache
    input output InstNode node;
    input InstNode packageNode;
    input PackageCacheState state;
  algorithm
    () := match node
      case CLASS_NODE() algorithm CachedData.setPackageCache(node.caches, CachedData.PACKAGE(packageNode, state)); then ();
      else algorithm Error.assertion(false, getInstanceName() + " got node without cache", sourceInfo()); then fail();
    end match;
  end setPackageCache;

  function clearPackageCache
    input output InstNode node;
  algorithm
    () := match node
      case CLASS_NODE() algorithm CachedData.clearPackageCache(node.caches); then ();
      else algorithm Error.assertion(false, getInstanceName() + " got node without cache", sourceInfo()); then fail();
    end match;
  end clearPackageCache;

  function openImplicitScope
    input output InstNode scope;
  algorithm
    scope := match scope
      case IMPLICIT_SCOPE() then scope;
      else IMPLICIT_SCOPE(scope, {});
    end match;
  end openImplicitScope;

  function explicitScope
    "Returns the first parent of the node that's not an implicit scope, or the
     node itself if it's not an implicit scope."
    input InstNode node;
    output InstNode scope;
  algorithm
    scope := match node
      case IMPLICIT_SCOPE() then explicitScope(node.parentScope);
      else node;
    end match;
  end explicitScope;

  function addIterator
    input InstNode iterator;
    input output InstNode scope;
  algorithm
    scope := match scope
      case IMPLICIT_SCOPE() then IMPLICIT_SCOPE(scope, iterator :: scope.locals);
    end match;
  end addIterator;

  function refEqual
    "Returns true if two nodes references the same class or component,
     otherwise false."
    input InstNode node1;
    input InstNode node2;
    output Boolean refEqual;
  algorithm
    refEqual := match (node1, node2)
      case (CLASS_NODE(), CLASS_NODE())
        then referenceEq(Pointer.access(node1.cls), Pointer.access(node2.cls));
      case (COMPONENT_NODE(), COMPONENT_NODE())
        then referenceEq(Pointer.access(node1.component), Pointer.access(node2.component));
      case (VAR_NODE(), VAR_NODE())
        then referenceEq(Pointer.access(node1.varPointer), Pointer.access(node2.varPointer));
      // Other nodes like ref nodes might be equal, but we neither know nor care.
      else false;
    end match;
  end refEqual;

  function refCompare
    input InstNode node1;
    input InstNode node2;
    output Integer res;
  algorithm
    res := match (node1, node2)
      case (CLASS_NODE(), CLASS_NODE())
        then Util.referenceCompare(Pointer.access(node1.cls), Pointer.access(node2.cls));
      case (COMPONENT_NODE(), COMPONENT_NODE())
        then Util.referenceCompare(Pointer.access(node1.component), Pointer.access(node2.component));
      case (CLASS_NODE(), COMPONENT_NODE())
        then Util.referenceCompare(Pointer.access(node1.cls), Pointer.access(node2.component));
      case (COMPONENT_NODE(), CLASS_NODE())
        then Util.referenceCompare(Pointer.access(node1.component), Pointer.access(node2.cls));
    end match;
  end refCompare;

  function nameEqual
    input InstNode node1;
    input InstNode node2;
    output Boolean equal = InstNode.name(node1) == InstNode.name(node2);
  end nameEqual;

  function isSame
    input InstNode node1;
    input InstNode node2;
    output Boolean same = false;
  protected
    InstNode n1 = resolveOuter(node1);
    InstNode n2 = resolveOuter(node2);
  algorithm
    if referenceEq(n1, n2) then
      same := true;
      return;
    end if;

    try
      same := referenceEq(definition(node1), definition(node2));
    else
      same := false;
    end try;
  end isSame;

  function checkIdentical
    input InstNode node1;
    input InstNode node2;
  protected
    InstNode n1 = resolveOuter(node1);
    InstNode n2 = resolveOuter(node2);
  algorithm
    if referenceEq(n1, n2) then
      return;
    end if;

    () := matchcontinue (n1, n2)
      case (CLASS_NODE(), CLASS_NODE())
        guard Class.isIdentical(getClass(n1), getClass(n2)) then ();
      case (COMPONENT_NODE(), COMPONENT_NODE())
        guard Component.isIdentical(component(n1), component(n2)) then ();
      else
        algorithm
          Error.addMultiSourceMessage(Error.DUPLICATE_ELEMENTS_NOT_IDENTICAL,
            {toString(n1), toString(n2)},
            {InstNode.info(n1), InstNode.info(n2)});
        then
          fail();
    end matchcontinue;
  end checkIdentical;

  function toString
    input InstNode node;
    output String name;
  algorithm
    name := match node
      case COMPONENT_NODE() then Component.toString(node.name, Pointer.access(node.component));
      case CLASS_NODE() then SCodeDump.unparseElementStr(node.definition);
      else name(node);
    end match;
  end toString;

  function toFlatString
    input InstNode node;
    input BaseModelica.OutputFormat format;
    input String indent;
    output String name;
  algorithm
    name := match node
      case COMPONENT_NODE() then Component.toFlatString(node.name, Pointer.access(node.component), format, indent);
      case CLASS_NODE() then Class.toFlatString(Pointer.access(node.cls), node, format, indent);
      else name(node);
    end match;
  end toFlatString;

  function toFlatStream
    input InstNode node;
    input BaseModelica.OutputFormat format;
    input String indent;
    input output IOStream.IOStream s;
  algorithm
    s := match node
      case COMPONENT_NODE() then Component.toFlatStream(node.name, Pointer.access(node.component), format, indent, s);
      case CLASS_NODE() then Class.toFlatStream(Pointer.access(node.cls), node, format, indent, s);
      else IOStream.append(s, toFlatString(node, format, indent));
    end match;
  end toFlatStream;

  function isRedeclare
    input InstNode node;
    output Boolean isRedeclare;
  algorithm
    isRedeclare := match node
      case CLASS_NODE() then SCodeUtil.isElementRedeclare(definition(node));
      case COMPONENT_NODE() then Component.isRedeclare(Pointer.access(node.component));
      else false;
    end match;
  end isRedeclare;

  function isRedeclared
    input InstNode node;
    output Boolean redeclared;
  algorithm
    redeclared := match nodeType(node)
      case InstNodeType.REDECLARED_COMP() then true;
      case InstNodeType.REDECLARED_CLASS() then true;
      else false;
    end match;
  end isRedeclared;

  function getRedeclaredNode
    input InstNode node;
    output InstNode outNode;
  algorithm
    outNode := match node
      case InstNode.CLASS_NODE(nodeType = InstNodeType.REDECLARED_CLASS(originalNode = SOME(outNode))) then outNode;
      else node;
    end match;
  end getRedeclaredNode;

  function isReplaceable
    input InstNode node;
    output Boolean repl;
  protected
    SCode.Element elem;
  algorithm
    repl := match node
      case CLASS_NODE() then SCodeUtil.isElementReplaceable(node.definition);
      case COMPONENT_NODE(definition = SOME(elem)) then SCodeUtil.isElementReplaceable(elem);
      else false;
    end match;
  end isReplaceable;

  function isProtectedBaseClass
    input InstNode node;
    output Boolean isProtected;
  algorithm
    isProtected := match node
      case CLASS_NODE(nodeType = InstNodeType.BASE_CLASS(definition =
          SCode.Element.EXTENDS(visibility = SCode.Visibility.PROTECTED())))
        then true;

      else false;
    end match;
  end isProtectedBaseClass;

  function visibility
    input InstNode node;
    output Visibility vis;
  algorithm
    vis := match node
      case CLASS_NODE() then node.visibility;
      case COMPONENT_NODE() then node.visibility;
      else Visibility.PUBLIC;
    end match;
  end visibility;

  function isProtected
    input InstNode node;
    output Boolean isProtected;
  algorithm
    isProtected := match node
      case CLASS_NODE(visibility = Visibility.PROTECTED) then true;
      case COMPONENT_NODE(visibility = Visibility.PROTECTED) then true;
      else false;
    end match;
  end isProtected;

  function isPublic
    input InstNode node;
    output Boolean isPublic = not isProtected(node);
  end isPublic;

  function protectClass
    input output InstNode cls;
  algorithm
    () := match cls
      case CLASS_NODE(visibility = Visibility.PUBLIC)
        algorithm
          cls.visibility := Visibility.PROTECTED;
        then
          ();

      else ();
    end match;
  end protectClass;

  function protectComponent
    input output InstNode comp;
  algorithm
    () := match comp
      case COMPONENT_NODE(visibility = Visibility.PUBLIC)
        algorithm
          comp.visibility := Visibility.PROTECTED;
        then
          ();

      else ();
    end match;
  end protectComponent;

  function protect
      input output InstNode node;
  algorithm
    () := match node
      case COMPONENT_NODE(visibility = Visibility.PUBLIC)
        algorithm
          node.visibility := Visibility.PROTECTED;
        then
          ();

      case CLASS_NODE(visibility = Visibility.PUBLIC)
        algorithm
          node.visibility := Visibility.PROTECTED;
        then
          ();

      else ();
    end match;
  end protect;

  function isEncapsulated
    input InstNode node;
    output Boolean enc;
  algorithm
    enc := match node
      case CLASS_NODE() then Class.isEncapsulated(Pointer.access(node.cls));
      case COMPONENT_NODE() then Class.isEncapsulated(getClass(node));
      else false;
    end match;
  end isEncapsulated;

  function getModifier
    input InstNode node;
    output Modifier mod;
  algorithm
    mod := match node
      case CLASS_NODE() then Class.getModifier(Pointer.access(node.cls));
      case COMPONENT_NODE() then Component.getModifier(Pointer.access(node.component));
      else Modifier.NOMOD();
    end match;
  end getModifier;

  function mergeModifier
    input Modifier mod;
    input output InstNode node;
  algorithm
    () := match node
      case CLASS_NODE()
        algorithm
          Pointer.update(node.cls, Class.mergeModifier(mod, Pointer.access(node.cls)));
        then
          ();

      case COMPONENT_NODE()
        algorithm
          Pointer.update(node.component, Component.mergeModifier(mod, Pointer.access(node.component)));
        then
          ();

      else ();
    end match;
  end mergeModifier;

  function setModifier
    input Modifier mod;
    input output InstNode node;
  algorithm
    () := match node
      case CLASS_NODE()
        algorithm
          Pointer.update(node.cls, Class.setModifier(mod, Pointer.access(node.cls)));
        then
          ();

      case COMPONENT_NODE()
        algorithm
          Pointer.update(node.component, Component.mergeModifier(mod, Pointer.access(node.component)));
        then
          ();

      else ();
    end match;
  end setModifier;

  function toPartialDAEType
    "Returns the DAE type for a class, without the list of variables filled in."
    input InstNode clsNode;
    output DAE.Type outType;
  algorithm
    outType := match clsNode
      local
        Class cls;
        ClassInf.State state;
        Restriction res;

      case CLASS_NODE()
        algorithm
          cls := Pointer.access(clsNode.cls);
        then
          match cls
            case Class.DAE_TYPE() then stripDAETypeVars(cls.ty);

            else
              algorithm
                res := Class.restriction(cls);
                state := Restriction.toDAE(res, fullPath(clsNode));
              then
                DAE.Type.T_COMPLEX(state, {}, NONE(), Restriction.isExternalRecord(res));

          end match;
    end match;
  end toPartialDAEType;

  function stripDAETypeVars
    input output DAE.Type ty;
  algorithm
    () := match ty
      case DAE.Type.T_COMPLEX()
        algorithm
          ty.varLst := {};
        then
          ();

      else ();
    end match;
  end stripDAETypeVars;

  function toFullDAEType
    "Returns the DAE type for a class, with the list of variables filled in."
    input InstNode clsNode;
    output DAE.Type outType;
  algorithm
    outType := match clsNode
      local
        Class cls;
        list<DAE.Var> vars;
        ClassInf.State state;
        Restriction res;

      case CLASS_NODE()
        algorithm
          cls := Pointer.access(clsNode.cls);
        then
          match cls
            case Class.DAE_TYPE() then cls.ty;

            else
              algorithm
                res := Class.restriction(cls);
                state := Restriction.toDAE(res, fullPath(clsNode));
                vars := ConvertDAE.makeTypeVars(clsNode);
                outType := DAE.Type.T_COMPLEX(state, vars, NONE(), Restriction.isExternalRecord(res));
                Pointer.update(clsNode.cls, Class.DAE_TYPE(outType));
              then
                outType;
          end match;
    end match;
  end toFullDAEType;

  function isBuiltin
    input InstNode node;
    output Boolean isBuiltin;
  algorithm
    isBuiltin := match node
      case CLASS_NODE() then isBuiltinNodeType(node.nodeType);
      else false;
    end match;
  end isBuiltin;

  function isBuiltinNodeType
    input InstNodeType nodeType;
    output Boolean isBuiltin;
  algorithm
    isBuiltin := match nodeType
      case InstNodeType.BUILTIN_CLASS() then true;
      case InstNodeType.BASE_CLASS() then isBuiltinNodeType(nodeType.ty);
      else false;
    end match;
  end isBuiltinNodeType;

  function isPartial
    input InstNode node;
    output Boolean isPartial;
  algorithm
    isPartial := match node
      case CLASS_NODE() then Class.isPartial(Pointer.access(node.cls));
      else false;
    end match;
  end isPartial;

  function clone
    input output InstNode node;
  algorithm
    () := match node
      local
        Class cls;
        Component comp;

      case CLASS_NODE()
        algorithm
          cls := Pointer.access(node.cls);
          cls := Class.classTreeApply(cls, ClassTree.clone);
          node.cls := Pointer.create(cls);
          node.caches := CachedData.empty();
        then
          ();

      case COMPONENT_NODE()
        algorithm
          comp := Pointer.access(node.component);
          comp := Component.setClassInstance(InstNode.clone(Component.classInstance(comp)), comp);
          node.component := Pointer.create(comp);
        then
          ();

      else ();
    end match;
  end clone;

  function cloneComponent
    input InstNode component;
    input InstNode newParent;
    output InstNode outComponent;
  algorithm
    outComponent := match component
      case COMPONENT_NODE()
        then COMPONENT_NODE(component.name, component.definition, component.visibility,
          Pointer.create(Pointer.access(component.component)), newParent, component.nodeType);
    end match;
  end cloneComponent;

  function getComments
    input InstNode node;
    input list<SCode.Comment> accumCmts = {};
    output list<SCode.Comment> cmts;
  algorithm
    cmts := match node
      local
        SCode.Comment cmt;
        Class cls;

      case CLASS_NODE(definition = SCode.CLASS(cmt = cmt))
        then cmt :: Class.getDerivedComments(Pointer.access(node.cls), accumCmts);

      else accumCmts;
    end match;
  end getComments;

  function copyInstancePtr
    input InstNode srcNode;
    input output InstNode dstNode;
  algorithm
    () := match (srcNode, dstNode)
      case (COMPONENT_NODE(), COMPONENT_NODE())
        algorithm
          dstNode.component := srcNode.component;
        then
          ();

      case (CLASS_NODE(), CLASS_NODE())
        algorithm
          dstNode.cls := srcNode.cls;
        then
          ();

    end match;
  end copyInstancePtr;

  function isRecord
    input InstNode node;
    output Boolean isRec;
  algorithm
    isRec := match node
      case CLASS_NODE() then Restriction.isRecord(Class.restriction(Pointer.access(node.cls)));
      case COMPONENT_NODE() then isRecord(Component.classInstance(Pointer.access(node.component)));
      else false;
    end match;
  end isRecord;

  function isModel
    input InstNode node;
    output Boolean isModel;
  algorithm
    isModel := match node
      case CLASS_NODE() then Restriction.isModel(Class.restriction(Pointer.access(node.cls)));
      case COMPONENT_NODE() then isModel(Component.classInstance(Pointer.access(node.component)));
      else false;
    end match;
  end isModel;

  function isEnumerationType
    input InstNode node;
    output Boolean isEnum = isClass(node) and Class.isEnumeration(getClass(resolveInner(node)));
  end isEnumerationType;

  function hasBinding
    input InstNode node;
    output Boolean hasBinding;
  algorithm
    hasBinding := match node
      case COMPONENT_NODE()
        then Component.hasBinding(Pointer.access(node.component)) or hasBinding(instanceParent(node));
      else false;
    end match;
  end hasBinding;

  function getBindingExpOpt
    input InstNode node;
    output Option<Expression> binding_exp;
  algorithm
    binding_exp := match node
      local
        Variable var;
      case COMPONENT_NODE() guard(Component.hasBinding(Pointer.access(node.component)))
        then Binding.getExpOpt(Component.getBinding(Pointer.access(node.component)));
      case COMPONENT_NODE()
        then getBindingExpOpt(instanceParent(node));
      case VAR_NODE() algorithm
          var := Pointer.access(node.varPointer);
        then Binding.getExpOpt(var.binding);
      else NONE();
    end match;
  end getBindingExpOpt;

  function getSections
    input InstNode node;
    output Sections sections;
  protected
    Class cls = InstNode.getClass(node);
  algorithm
    sections := match cls
      case Class.INSTANCED_CLASS() then cls.sections;
      case Class.TYPED_DERIVED() then getSections(cls.baseClass);

      else
        algorithm
          Error.assertion(false, getInstanceName() + " did not get an instanced class", sourceInfo());
        then fail();
    end match;
  end getSections;

  function hash
    "Returns the hash of an InstNode's name."
    input InstNode node;
    output Integer hash = stringHashDjb2(name(node));
  end hash;

  function dimensionCount
    input InstNode node;
    output Integer count;
  algorithm
    count := match node
      case COMPONENT_NODE() then Component.dimensionCount(Pointer.access(node.component));
      case CLASS_NODE() then Class.dimensionCount(Pointer.access(node.cls));
      else 0;
    end match;
  end dimensionCount;

  function isClockType
    input InstNode node;
    output Boolean clock;
  algorithm
    clock := match node
      case CLASS_NODE(name = "Clock", nodeType = InstNodeType.BUILTIN_CLASS()) then true;
      else false;
    end match;
  end isClockType;

  function restriction
    input InstNode node;
    output Restriction res;
  algorithm
    res := match node
      case CLASS_NODE() then Class.restriction(Pointer.access(node.cls));
      case COMPONENT_NODE() then restriction(Component.classInstance(Pointer.access(node.component)));
      case INNER_OUTER_NODE() then restriction(node.innerNode);
      else Restriction.UNKNOWN();
    end match;
  end restriction;

  function isExtends
    input InstNode node;
    output Boolean res;
  algorithm
    res := match node
      case CLASS_NODE(definition = SCode.Element.EXTENDS()) then true;
      case CLASS_NODE(nodeType = InstNodeType.BASE_CLASS(definition = SCode.Element.EXTENDS())) then true;
      else false;
    end match;
  end isExtends;

  function isDiscreteClass
    input InstNode clsNode;
    output Boolean isDiscrete;
  protected
    InstNode base_node;
    Class cls;
    array<InstNode> exts;
  algorithm
    base_node := Class.lastBaseClass(clsNode);
    cls := InstNode.getClass(base_node);

    isDiscrete := match cls
      case Class.EXPANDED_CLASS(restriction = Restriction.TYPE())
        algorithm
          exts := ClassTree.getExtends(cls.elements);
        then
          if arrayLength(exts) == 1 then isDiscreteClass(exts[1]) else false;

      else Type.isDiscrete(Class.getType(cls, base_node));
    end match;
  end isDiscreteClass;

  function clearGeneratedInners
    input InstNode node;
  protected
    InstNode top;
    UnorderedMap<String, InstNode> inners;
  algorithm
    InstNodeType.TOP_SCOPE(generatedInners = inners) := nodeType(InstNode.topScope(node));
    UnorderedMap.clear(inners);
  end clearGeneratedInners;

  function getAccessLevel
    input InstNode node;
    output Option<AccessLevel> access = NONE();
  protected
    InstNode scope;
    SCode.Mod access_mod;
    Option<Absyn.Exp> access_exp;
  algorithm
    scope := classScope(parent(resolveInner(node)));

    while isClass(scope) loop
      access_mod := SCodeUtil.lookupElementAnnotation(definition(scope), "Protection");
      access_mod := SCodeUtil.lookupModInMod("access", access_mod);
      access_exp := SCodeUtil.getModifierBinding(access_mod);

      if isSome(access_exp) then
        access := Prefixes.accessLevelFromAbsyn(Util.getOption(access_exp));

        if isSome(access) then
          return;
        end if;
      end if;

      scope := parent(scope);
    end while;
  end getAccessLevel;
end InstNode;

annotation(__OpenModelica_Interface="frontend");
end NFInstNode;
