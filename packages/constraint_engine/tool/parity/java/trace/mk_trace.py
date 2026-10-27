#!/usr/bin/env python3
"""TraceJava: patch the pinned solver sources with trace hooks (FORMATS.md 7b).

  python3 -I mk_trace.py <upstream core sources> <out dir>

<upstream core sources> is constraintlayout/core/src/main/java of the upstream checkout at
the pin. Reads LinearSystem, ArrayRow, ArrayLinkedVariables, PriorityGoalRow and
SolverVariable from it, applies each (anchor, replacement) edit once (an anchor must occur
exactly once), and writes the patched files to <out dir>/androidx/constraintlayout/core/.
Every hook is guarded by `SolverTrace.sb != null` and only reads state, so without a sink
the classes behave as upstream. build_trace.sh runs it and compiles the result.
"""
import os
import sys

PKG = 'androidx/constraintlayout/core/'
ON = 'if (SolverTrace.sb != null) '

EDITS = {
    'LinearSystem.java': [
        # RS: reset() entry.
        ('    public void reset() {\n        if (DEBUG) {\n'
         '            System.out.println("##################");\n'
         '            System.out.println("## RESET SYSTEM ##");',
         '    public void reset() {\n        ' + ON + 'SolverTrace.line("RS");\n'
         '        if (DEBUG) {\n'
         '            System.out.println("##################");\n'
         '            System.out.println("## RESET SYSTEM ##");'),
        # V U: createObjectVariable assigns a new id.
        ('                variable.mType = SolverVariable.Type.UNRESTRICTED;\n'
         '                mCache.mIndexedVariables[mVariablesID] = variable;\n',
         '                variable.mType = SolverVariable.Type.UNRESTRICTED;\n'
         '                mCache.mIndexedVariables[mVariablesID] = variable;\n'
         '                ' + ON + 'SolverTrace.newVariable(variable, \'U\', 0,\n'
         '                        SolverTrace.anchorName((ConstraintAnchor) anchor));\n'),
        # V S: createSlackVariable.
        ('            sMetrics.slackvariables++;\n        }\n'
         '        if (mNumColumns + 1 >= mMaxColumns) {\n            increaseTableSize();\n        }\n'
         '        SolverVariable variable = acquireSolverVariable(SolverVariable.Type.SLACK, null);\n'
         '        mVariablesID++;\n        mNumColumns++;\n        variable.id = mVariablesID;\n'
         '        mCache.mIndexedVariables[mVariablesID] = variable;\n',
         '            sMetrics.slackvariables++;\n        }\n'
         '        if (mNumColumns + 1 >= mMaxColumns) {\n            increaseTableSize();\n        }\n'
         '        SolverVariable variable = acquireSolverVariable(SolverVariable.Type.SLACK, null);\n'
         '        mVariablesID++;\n        mNumColumns++;\n        variable.id = mVariablesID;\n'
         '        mCache.mIndexedVariables[mVariablesID] = variable;\n'
         '        ' + ON + 'SolverTrace.newVariable(variable, \'S\', 0, null);\n'),
        # V X: createExtraVariable.
        ('            sMetrics.extravariables++;\n        }\n'
         '        if (mNumColumns + 1 >= mMaxColumns) {\n            increaseTableSize();\n        }\n'
         '        SolverVariable variable = acquireSolverVariable(SolverVariable.Type.SLACK, null);\n'
         '        mVariablesID++;\n        mNumColumns++;\n        variable.id = mVariablesID;\n'
         '        mCache.mIndexedVariables[mVariablesID] = variable;\n',
         '            sMetrics.extravariables++;\n        }\n'
         '        if (mNumColumns + 1 >= mMaxColumns) {\n            increaseTableSize();\n        }\n'
         '        SolverVariable variable = acquireSolverVariable(SolverVariable.Type.SLACK, null);\n'
         '        mVariablesID++;\n        mNumColumns++;\n        variable.id = mVariablesID;\n'
         '        mCache.mIndexedVariables[mVariablesID] = variable;\n'
         '        ' + ON + 'SolverTrace.newVariable(variable, \'X\', 0, null);\n'),
        # V N: createVariable(name, type).
        ('        mVariables.put(name, variable);\n'
         '        mCache.mIndexedVariables[mVariablesID] = variable;\n        return variable;',
         '        mVariables.put(name, variable);\n'
         '        mCache.mIndexedVariables[mVariablesID] = variable;\n'
         '        ' + ON + 'SolverTrace.newVariable(variable, \'N\', 0, name);\n'
         '        return variable;'),
        # V E: createErrorVariable, before the goal sees it.
        ('        variable.strength = strength;\n'
         '        mCache.mIndexedVariables[mVariablesID] = variable;\n'
         '        mGoal.addError(variable);',
         '        variable.strength = strength;\n'
         '        mCache.mIndexedVariables[mVariablesID] = variable;\n'
         '        ' + ON + 'SolverTrace.newVariable(variable, \'E\', strength, null);\n'
         '        mGoal.addError(variable);'),
        # O: getObjectVariableValue (same float expression, same cast).
        ('        SolverVariable variable = anchor.getSolverVariable();\n'
         '        if (variable != null) {\n'
         '            return (int) (variable.computedValue + 0.5f);\n'
         '        }\n        return 0;',
         '        SolverVariable variable = anchor.getSolverVariable();\n'
         '        if (variable != null) {\n'
         '            int traceValue = (int) (variable.computedValue + 0.5f);\n'
         '            ' + ON + 'SolverTrace.readback(variable, traceValue);\n'
         '            return traceValue;\n'
         '        }\n'
         '        ' + ON + 'SolverTrace.readback(null, 0);\n'
         '        return 0;'),
        # MZ: minimize() entry.
        ('            sMetrics.minimize++;\n        }\n        if (mGoal.isEmpty()) {',
         '            sMetrics.minimize++;\n        }\n'
         '        ' + ON + 'SolverTrace.minimize(mNumRows, mNumColumns, mGoal.isEmpty());\n'
         '        if (mGoal.isEmpty()) {'),
        # A: addConstraint entry.
        ('    public void addConstraint(ArrayRow row) {\n        if (row == null) {\n'
         '            return;\n        }\n',
         '    public void addConstraint(ArrayRow row) {\n        if (row == null) {\n'
         '            return;\n        }\n'
         '        ' + ON + 'SolverTrace.addConstraint(row);\n'),
        # U and D E: after updateFromSystem.
        ('            row.updateFromSystem(this);\n\n            if (row.isEmpty()) {\n'
         '                return;\n            }',
         '            row.updateFromSystem(this);\n'
         '            ' + ON + 'SolverTrace.updated(row);\n\n'
         '            if (row.isEmpty()) {\n'
         '                ' + ON + 'SolverTrace.line("D E");\n'
         '                return;\n            }'),
        # R: after chooseSubject (called once, as upstream).
        ('            if (row.chooseSubject(this)) {',
         '            boolean traceExtra = row.chooseSubject(this);\n'
         '            ' + ON + 'SolverTrace.subject(row, traceExtra);\n'
         '            if (traceExtra) {'),
        # RX: the extra variable left the basis and the row was released.
        ('                            mCache.mArrayRowPool.release(row);\n'
         '                        }\n                        mNumRows--;\n',
         '                            mCache.mArrayRowPool.release(row);\n'
         '                        }\n                        mNumRows--;\n'
         '                        ' + ON + 'SolverTrace.removedExtra(row);\n'),
        # D K: no key variable.
        ('                    displayReadableRows();\n                }\n'
         '                return;\n            }\n        }\n        if (!added) {',
         '                    displayReadableRows();\n                }\n'
         '                ' + ON + 'SolverTrace.line("D K");\n'
         '                return;\n            }\n        }\n        if (!added) {'),
        # AF and AR: addRow.
        ('        if (SIMPLIFY_SYNONYMS && row.mIsSimpleDefinition) {\n'
         '            row.mVariable.setFinalValue(this, row.mConstantValue);\n'
         '        } else {\n            mRows[mNumRows] = row;\n'
         '            row.mVariable.mDefinitionId = mNumRows;\n            mNumRows++;',
         '        if (SIMPLIFY_SYNONYMS && row.mIsSimpleDefinition) {\n'
         '            ' + ON + 'SolverTrace.addFinal(row);\n'
         '            row.mVariable.setFinalValue(this, row.mConstantValue);\n'
         '        } else {\n            mRows[mNumRows] = row;\n'
         '            row.mVariable.mDefinitionId = mNumRows;\n'
         '            ' + ON + 'SolverTrace.addRow(mNumRows, row);\n'
         '            mNumRows++;'),
        # CP: addRow's compaction.
        ('                    ArrayRow removedRow = mRows[i];\n'
         '                    removedRow.mVariable.setFinalValue(this, removedRow.mConstantValue);',
         '                    ArrayRow removedRow = mRows[i];\n'
         '                    ' + ON + 'SolverTrace.compact(i, removedRow);\n'
         '                    removedRow.mVariable.setFinalValue(this, removedRow.mConstantValue);'),
        # OE cap.
        ('                            + tries + " >= " + (2 * mNumColumns));\n'
         '                }\n                return tries;',
         '                            + tries + " >= " + (2 * mNumColumns));\n'
         '                }\n'
         '                ' + ON + 'SolverTrace.optimizeEnd(b, tries, "cap");\n'
         '                return tries;'),
        # C: optimize candidate.
        ('            SolverVariable pivotCandidate = goal.getPivotCandidate(this, mAlreadyTestedCandidates);\n',
         '            SolverVariable pivotCandidate = goal.getPivotCandidate(this, mAlreadyTestedCandidates);\n'
         '            ' + ON + 'SolverTrace.candidate(b, tries, pivotCandidate);\n'),
        # OE tested.
        ('                                + " already tested, let\'s bail");\n'
         '                    }\n                    return tries;',
         '                                + " already tested, let\'s bail");\n'
         '                    }\n'
         '                    ' + ON + 'SolverTrace.optimizeEnd(b, tries, "tested");\n'
         '                    return tries;'),
        # P: optimize pivot choice.
        ('                        System.out.println("We pivot on " + pivotRowIndex);\n'
         '                    }\n                    ArrayRow pivotEquation = mRows[pivotRowIndex];\n',
         '                        System.out.println("We pivot on " + pivotRowIndex);\n'
         '                    }\n                    ArrayRow pivotEquation = mRows[pivotRowIndex];\n'
         '                    ' + ON + 'SolverTrace.pivotChoice(pivotRowIndex, pivotCandidate, b);\n'),
        # NP: no pivot row.
        ('                        System.out.println("we couldn\'t find an equation to pivot upon");\n'
         '                    }\n',
         '                        System.out.println("we couldn\'t find an equation to pivot upon");\n'
         '                    }\n'
         '                    ' + ON + 'SolverTrace.noPivot(b);\n'),
        # OE done.
        ('                    System.out.println("no more candidate goals to pivot on, let\'s exit");\n'
         '                }\n                done = true;\n            }\n        }\n        return tries;',
         '                    System.out.println("no more candidate goals to pivot on, let\'s exit");\n'
         '                }\n                done = true;\n            }\n        }\n'
         '        ' + ON + 'SolverTrace.optimizeEnd(b, tries, "done");\n'
         '        return tries;'),
        # BF: enforceBFS after its scan.
        ('        // The system happens to not be in BFS form, we need to go back to it to properly solve it.\n'
         '        if (infeasibleSystem) {',
         '        ' + ON + 'SolverTrace.bfs(infeasibleSystem);\n'
         '        // The system happens to not be in BFS form, we need to go back to it to properly solve it.\n'
         '        if (infeasibleSystem) {'),
        # B: enforceBFS pivot.
        ('                    // We have a pivot!\n'
         '                    ArrayRow pivotEquation = mRows[pivotRowIndex];\n',
         '                    // We have a pivot!\n'
         '                    ArrayRow pivotEquation = mRows[pivotRowIndex];\n'
         '                    ' + ON + 'SolverTrace.bfsPivot(pivotRowIndex, pivotColumnIndex);\n'),
        # F: computeValues.
        ('            ArrayRow row = mRows[i];\n'
         '            row.mVariable.computedValue = row.mConstantValue;\n',
         '            ArrayRow row = mRows[i];\n'
         '            row.mVariable.computedValue = row.mConstantValue;\n'
         '            ' + ON + 'SolverTrace.computed(row);\n'),
        # Q: addEquality(var, int) entry.
        ('    public void addEquality(SolverVariable a, int value) {\n',
         '    public void addEquality(SolverVariable a, int value) {\n'
         '        ' + ON + 'SolverTrace.equality(a, value);\n'),
    ],
    'ArrayRow.java': [
        # PI: every pivot, after it.
        ('    void pivot(SolverVariable v) {\n        if (mVariable != null) {',
         '    void pivot(SolverVariable v) {\n        SolverVariable traceLeaving = mVariable;\n'
         '        if (mVariable != null) {'),
        ('        mVariable = v;\n        if (amount == 1) {\n            return;\n        }\n'
         '        mConstantValue = mConstantValue / amount;\n'
         '        variables.divideByAmount(amount);\n    }',
         '        mVariable = v;\n        if (amount == 1) {\n'
         '            ' + ON + 'SolverTrace.pivot(traceLeaving, v, amount, this);\n'
         '            return;\n        }\n'
         '        mConstantValue = mConstantValue / amount;\n'
         '        variables.divideByAmount(amount);\n'
         '        ' + ON + 'SolverTrace.pivot(traceLeaving, v, amount, this);\n    }'),
    ],
    'ArrayLinkedVariables.java': [
        # traceTo: the list in order, without allocation or side effects.
        ('            current = mArrayNextIndices[current];\n            counter++;\n        }\n'
         '        return result;\n    }\n\n}',
         '            current = mArrayNextIndices[current];\n            counter++;\n        }\n'
         '        return result;\n    }\n\n'
         '    /** TraceJava: {@code <n> <v>:<f> ...} in list order (FORMATS.md 7b). */\n'
         '    void traceTo(StringBuilder b) {\n'
         '        b.append(mCurrentSize);\n'
         '        int current = mHead;\n'
         '        int counter = 0;\n'
         '        while (current != NONE && counter < mCurrentSize) {\n'
         '            b.append(\' \').append(mArrayIndices[current]).append(\':\');\n'
         '            SolverTrace.f(b, mArrayValues[current]);\n'
         '            current = mArrayNextIndices[current];\n'
         '            counter++;\n'
         '        }\n'
         '    }\n\n}'),
    ],
    'PriorityGoalRow.java': [
        # G: addError.
        ('        error.mGoalStrengthVector[error.strength] = 1;\n        addToGoal(error);\n',
         '        error.mGoalStrengthVector[error.strength] = 1;\n        addToGoal(error);\n'
         '        ' + ON + 'SolverTrace.goalVector(error);\n'),
        # GR: removeGoal.
        ('                mNumGoals--;\n                variable.inGoal = false;\n                return;',
         '                mNumGoals--;\n                variable.inGoal = false;\n'
         '                ' + ON + 'SolverTrace.goalRemoved(variable);\n'
         '                return;'),
        # G: updateFromRow, each variable still in the goal.
        ('            if (mAccessor.addToGoal(goalVariable, value)) {\n'
         '                addToGoal(solverVariable);\n            }\n',
         '            if (mAccessor.addToGoal(goalVariable, value)) {\n'
         '                addToGoal(solverVariable);\n            }\n'
         '            ' + ON + '{\n'
         '                if (solverVariable.inGoal) SolverTrace.goalVector(solverVariable);\n'
         '            }\n'),
    ],
    'SolverVariable.java': [
        # FV: setFinalValue entry.
        ('    public void setFinalValue(LinearSystem system, float value) {\n',
         '    public void setFinalValue(LinearSystem system, float value) {\n'
         '        ' + ON + 'SolverTrace.finalValue(this, value);\n'),
        # SY: setSynonym entry.
        ('    public void setSynonym(LinearSystem system, SolverVariable synonymVariable, float value) {\n',
         '    public void setSynonym(LinearSystem system, SolverVariable synonymVariable, float value) {\n'
         '        ' + ON + 'SolverTrace.synonym(this, synonymVariable, value);\n'),
    ],
}


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.split('\n\n')[1])
    UP = os.path.join(sys.argv[1], PKG)
    OUT = os.path.join(sys.argv[2], PKG)
    os.makedirs(OUT, exist_ok=True)
    total = 0
    for name, edits in EDITS.items():
        src = open(UP + name, encoding='utf-8').read()
        for i, (old, new) in enumerate(edits):
            n = src.count(old)
            if n != 1:
                sys.exit(f'{name}: edit {i} anchor found {n} times')
            src = src.replace(old, new)
            total += 1
        header = ('// TraceJava: upstream ' + name + ' at the pin with trace\n'
                  '// hooks generated by mk_trace.py. Do not edit; regenerate.\n')
        open(OUT + name, 'w', encoding='utf-8').write(header + src)
    print(f'patched {len(EDITS)} files, {total} edits -> {OUT}')


main()
