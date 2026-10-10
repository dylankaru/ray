import Foundation
import JavaScriptCore


final class CASEngine {
    static let shared = CASEngine()
    private let context: JSContext
    
    private init() {
        context = JSContext()!
        context.exceptionHandler = { _, _ in }
        
        // 1. Load math.js core
        if let path = Bundle.main.path(forResource: "math", ofType: "js"),
           let script = try? String(contentsOfFile: path) {
            context.evaluateScript(script)
        }
        
        // 2. Inject ClassPad CAS Engine Helpers
        let classpadHelpers = """
        // --- ClassPad Syntax Preprocessor ---
        function preprocessClassPad(raw) {
            if (!raw || !raw.trim()) return "";
            let q = raw.trim();

            // Auto-wrap bare equations: "5x = 2" -> "solve(5x = 2)"
            if (q.includes('=') && !q.toLowerCase().startsWith('solve(')) {
                q = `solve(${q})`;
            }

            // 1. Implicit Multiplication Transforms
            q = q.replace(/(\\d)([a-zA-Z])/g, '$1*$2');        // 5x -> 5*x
            q = q.replace(/(\\d)\\(/g, '$1*(');                 // 5( -> 5*(             q = q.replace(/\\)(\\d)/g, ')*$1');                 // )5 -> )*5
            q = q.replace(/\\)\\(/g, ')*(');                   // )( -> )*(             q = q.replace(/\\)([a-zA-Z])/g, ')*$1');            // )x -> )*x

            // Protect function calls from implicit mult (e.g., sin(, diff()
            const reserved = ["sin","cos","tan","asin","acos","atan","log","ln","sqrt","diff","solve","expand","simplify","factor","det","inv"];
            let placeholders = [];
            reserved.forEach((fn, idx) => {
                let reg = new RegExp('\\\\b' + fn + '\\\\(', 'gi');
                q = q.replace(reg, (m) => {
                    placeholders.push(m);
                    return `__FN_${placeholders.length - 1}__`;
                });
            });

            // Convert remaining letter-before-paren: x( -> x*(
            q = q.replace(/([a-zA-Z]+)\\(/g, '$1*(');

            // Restore reserved functions
            placeholders.forEach((m, idx) => {
                q = q.replace(`__FN_${idx}__`, m);
            });

            return q;
        }

        // --- ClassPad Equation Solver ---
        function classpadSolve(eqStr, varName) {
            varName = varName || 'x';
            let lhs = eqStr, rhs = '0';
            if (eqStr.includes('=')) {
                let parts = eqStr.split('=');
                lhs = parts[0];
                rhs = parts[1];
            }
            let exprStr = `(${lhs}) - (${rhs})`;

            try {
                // Rationalize to polynomial form
                let rationalized = math.rationalize(exprStr, {}, true);
                let coeffs = rationalized.coefficients;

                if (coeffs && coeffs.length > 0) {
                    let numCoeffs = coeffs.map(c => math.evaluate(c.toString()));
                    
                    // Linear: c0 + c1*x = 0
                    if (numCoeffs.length === 2) {
                        let root = math.divide(math.unaryMinus(numCoeffs[0]), numCoeffs[1]);
                        return `${varName} = ${math.format(root, {precision: 10})}`;
                    } 
                    // Quadratic & Higher Polynomials
                    else if (numCoeffs.length > 2) {
                        let roots = math.polynomialRoot(...numCoeffs);
                        let formatted = roots.map(r => typeof r === 'number' ? math.format(r, {precision: 10}) : r.toString());
                        return `${varName} = ${formatted.join(' or ')}`;
                    }
                }
            } catch (e) {}

            return "Unable to solve";
        }

        // --- ClassPad Function Wrapper ---
        function executeClassPad(rawQuery) {
            let q = preprocessClassPad(rawQuery);
            if (!q) return null;

            // ClassPad Command Matching
            if (q.startsWith('solve(') && q.endsWith(')')) {
                let body = q.substring(6, q.length - 1);
                let args = body.split(',');
                let eq = args[0];
                let v = args[1] ? args[1].trim() : 'x';
                return classpadSolve(eq, v);
            }

            if (q.startsWith('diff(') && q.endsWith(')')) {
                let body = q.substring(5, q.length - 1);
                let args = body.split(',');
                let expr = args[0];
                let v = args[1] ? args[1].trim() : 'x';
                let res = math.derivative(expr, v);
                return res.toString();
            }

            if (q.startsWith('expand(') && q.endsWith(')')) {
                let body = q.substring(7, q.length - 1);
                return math.rationalize(body).toString();
            }

            if (q.startsWith('simplify(') && q.endsWith(')')) {
                let body = q.substring(9, q.length - 1);
                return math.simplify(body).toString();
            }

            if (q.startsWith('factor(') && q.endsWith(')')) {
                let body = q.substring(7, q.length - 1);
                return math.simplify(body).toString();
            }

            // Standard Math Evaluation with Implicit Mult support
            let res = math.evaluate(q);
            if (res === undefined || res === null) return null;
            if (typeof res === 'object' && res.isNode) return res.toString();
            return math.format(res, { precision: 10 });
        }
        """
        context.evaluateScript(classpadHelpers)
    }
    
    func evaluate(_ query: String) -> String? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: [query]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        
        let jsCommand = """
        (function() {
            try {
                return executeClassPad(\(jsonString)[0]);
            } catch (e) {
                return null;
            }
        })()
        """
        
        guard let result = context.evaluateScript(jsCommand), !result.isNull, !result.isUndefined else {
            return nil
        }
        return result.toString()
    }
    
    func toLaTeX(_ query: String) -> String? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: [query]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        
        let jsCommand = """
        (function() {
            try {
                let q = preprocessClassPad(\(jsonString)[0]);
                return math.parse(q).toTex();
            } catch (e) {
                return null;
            }
        })()
        """
        
        guard let result = context.evaluateScript(jsCommand), !result.isNull, !result.isUndefined else {
            return nil
        }
        return result.toString()
    }
}
