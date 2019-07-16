// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/protocol/protocol_generated.dart' as protocol;
import 'package:analysis_server/src/protocol_server.dart' as protocol;
import 'package:analysis_server/src/services/flutter/class_description.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

class PropertyDescription {
  final PropertyDescription _parent;

  /// The resolved unit, where the property value is.
  final ResolvedUnitResult _resolvedUnit;

  /// If the object that has this property is not materialized yet, so the
  /// [_instanceCreation] is `null` description of the object for materialize.
  final ClassDescription _classDescription;

  /// The instance creation of the object that has this property. Or `null`
  /// if the object is not materialized yet, in this case [_classDescription]
  /// is set.
  final InstanceCreationExpression _instanceCreation;

  /// If the property is set, the full argument expression, might be
  /// [NamedExpression].
  final Expression _argumentExpression;

  /// If the property is set, the value part of the argument expression,
  /// the same as [_argumentExpression] if a positional argument, or the
  /// expression part of the [NamedExpression].
  final Expression _valueExpression;

  /// The parameter element in the object constructor that is actually
  /// invoked by [_instanceCreation], or will be invoked when
  /// [_classDescription] is materialized.
  final ParameterElement _parameterElement;

  /// Optional nested properties.
  final List<PropertyDescription> children = [];

  final protocol.FlutterWidgetProperty protocolProperty;

  PropertyDescription(
    this._parent,
    this._resolvedUnit,
    this._classDescription,
    this._instanceCreation,
    this._argumentExpression,
    this._valueExpression,
    this._parameterElement,
    this.protocolProperty,
  );

  Future<protocol.SourceChange> changeValue(
      protocol.FlutterWidgetPropertyValue value) async {
    var changeBuilder = DartChangeBuilder(_resolvedUnit.session);

    await changeBuilder.addFileEdit(_resolvedUnit.path, (builder) {
      _changeCode(builder, (builder) {
        var code = _toCode(value);
        builder.write(code);
      });
    });

    return changeBuilder.sourceChange;
  }

  Future<protocol.SourceChange> removeValue() async {
    var changeBuilder = DartChangeBuilder(_resolvedUnit.session);

    if (_argumentExpression != null) {
      int endOffset;
      var argumentList = _instanceCreation.argumentList;
      var arguments = argumentList.arguments;
      var argumentIndex = arguments.indexOf(_argumentExpression);
      if (argumentIndex < arguments.length - 1) {
        endOffset = arguments[argumentIndex + 1].offset;
      } else {
        endOffset = argumentList.rightParenthesis.offset;
      }

      var beginOffset = _argumentExpression.offset;
      await changeBuilder.addFileEdit(_resolvedUnit.path, (builder) {
        builder.addDeletion(
          SourceRange(beginOffset, endOffset - beginOffset),
        );
      });
    }

    return changeBuilder.sourceChange;
  }

  void _changeCode(
    DartFileEditBuilder builder,
    void buildCode(DartEditBuilder builder),
  ) {
    if (_valueExpression != null) {
      builder.addReplacement(range.node(_valueExpression), buildCode);
    } else {
      if (_instanceCreation != null) {
        var argumentList = _instanceCreation.argumentList;
        var rightParenthesis = argumentList.rightParenthesis;

        // TODO(scheglov) Insert sorted by names.
        builder.addInsertion(rightParenthesis.offset, (builder) {
          var previous = rightParenthesis.previous;
          if (previous.type != TokenType.COMMA &&
              previous != argumentList.leftParenthesis) {
            builder.write(', ');
          }

          builder.write(_parameterElement.name);
          builder.write(': ');

          buildCode(builder);
          builder.write(', ');
        });
      } else {
        _parent._changeCode(builder, (builder) {
          builder.writeReference(_classDescription.element);
          // TODO(scheglov) constructor name
          builder.write('(');
          builder.write(_parameterElement.name);
          builder.write(': ');
          buildCode(builder);
          builder.write(', ');
          builder.write(')');
        });
      }
    }
  }

  /// TODO(scheglov) Use builder.
  String _toCode(protocol.FlutterWidgetPropertyValue value) {
    if (value.boolValue != null) {
      return '${value.boolValue}';
    }

    if (value.doubleValue != null) {
      return value.doubleValue.toStringAsFixed(1);
    }

    if (value.intValue != null) {
      return '${value.intValue}';
    }

    if (value.stringValue != null) {
      var code = value.stringValue;
      if (code.contains("'")) {
        code = code.replaceAll("'", r"\'");
      }
      return "'$code'";
    }

    throw StateError('Cannot how to encode: $value');
  }
}
