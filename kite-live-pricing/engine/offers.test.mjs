// Runs Kite's compiled custom-discount-builder function against the three demo offers.
// Usage: node engine/offers.test.mjs path/to/consolidated-discounts-v2.wasm
import fs from 'fs';
import assert from 'assert/strict';
import { runFunction } from './run-function.mjs';

const wasm = fs.readFileSync(process.argv[2]);
const P = ['101', '102', '103', '104', '105'];
const PRICES = [24, 32, 28, 40, 18];

const line = (i, props) => ({
  cost: { amountPerQuantity: { amount: String(PRICES[i % 5]) } }, quantity: 1, id: `gid://shopify/CartLine/${i}`, sellingPlanAllocation: null,
  merchandise: { __typename: 'ProductVariant', id: `gid://shopify/ProductVariant/${P[i % 5]}0`, product: { id: `gid://shopify/Product/${P[i % 5]}`, inCollections: [], hasTags: [], productType: '' } },
  lineAttributeKey1: props ? { key: '_kite_bundle', value: 'routine' } : null,
});
const input = (lines, cfg) => ({
  cart: { CFData: { value: '{}' }, cartAttributeKey1: null, lines, cost: { subtotalAmount: { amount: '0', currencyCode: 'USD' } }, buyerIdentity: { isAuthenticated: false, customer: null }, retailLocation: null },
  localization: { market: { handle: 'us' } }, presentmentCurrencyRate: '1.0', discount: { metafield: { value: JSON.stringify(cfg) } },
});
const gate = { rulesGlobalOperator: 'AND', rulesGlobalList: [{ rulesOperator: 'AND', rulesList: [] }] };
const prodRule = (n) => ({ ruleType: 'products', type: 'PRODUCT', ruleValue: { operatorType: 'include', value: P, qualifierType: 'overallQty', qualifierOperatorType: 'greaterThanOrEqualTo', qualifierValue: n } });
const seg = (extra) => ({ discountType: 'PERCENTAGE', appliesToEachItem: true, sortByOrder: 'ascending', sortBasedOn: 'productPrice', ...extra });
const base = { discountFunctionType: 'CONSOLIDATED_CUSTOM_DISCOUNT', discountTitle: 't', metricsArray: ['products'], discountTriggeredRulesData: gate };

const tiered = { ...base, segmentsData: { discountApplicationStrategy: 'MAXIMUM', segmentsList: [[3, 10], [4, 15], [5, 20]].map(([n, pct]) => seg({ discountValue: pct, message: `${pct}%`, buyXRulesData: { rulesOperator: 'AND', rulesList: [prodRule(n)] }, getYRulesData: { rulesOperator: 'OR', rulesList: [prodRule(0)] } })) } };
const bxgy = { ...base, segmentsData: { discountApplicationStrategy: 'ALL', segmentsList: [seg({ discountValue: 10, message: '3rd', totalLimit: 1, buyXRulesData: { rulesOperator: 'AND', rulesList: [prodRule(3)] }, getYRulesData: { rulesOperator: 'OR', itemCount: 1, rulesList: [prodRule(0)] } })] } };
const attr = { ruleType: 'lineAttributes', type: 'PRODUCT', ruleValue: { operatorType: 'include', attributeKey: { operatorType: 'is', value: '_kite_bundle' }, attributeValue: { operatorType: 'is', value: 'routine' }, qualifierType: 'overallQty', qualifierOperatorType: 'greaterThanOrEqualTo', qualifierValue: 0 } };
const set = { ...base, lineAttributeKey1: '_kite_bundle', metricsArray: ['products', 'lineAttributes'], segmentsData: { discountApplicationStrategy: 'ALL', segmentsList: [{ discountType: 'FIXED_PRICE', discountValue: 75, message: 'set', appliesToEachItem: false, sortByOrder: 'descending', sortBasedOn: 'productPrice', totalLimit: 3, buyXRulesData: { rulesOperator: 'AND', rulesList: [prodRule(3)] }, getYRulesData: { rulesOperator: 'AND', itemCount: 3, rulesList: [prodRule(0), attr] } }] } };

const candidates = async (n, cfg, props = false) => {
  const r = await runFunction(wasm, 'generate_cart_run', input([...Array(n).keys()].map(i => line(i, props)), cfg));
  return JSON.parse(r.stdout).operations[0].productDiscountsAdd.candidates;
};

assert.equal((await candidates(2, tiered)).length, 0);
assert.deepEqual((await candidates(4, tiered)).map(c => c.value.percentage.value), ['10.0', '15.0']);
const b = await candidates(3, bxgy);
assert.equal(b.length, 1);
assert.equal(b[0].targets[0].cartLine.id, 'gid://shopify/CartLine/0'); // cheapest of 24/32/28
assert.equal((await candidates(3, set, false)).length, 0);              // no _kite_bundle → no discount
assert.equal((await candidates(3, set, true))[0].value.fixedAmount.amount, '9.0'); // 84 − 75
console.log('ok: tiered, buy-2-get-3rd and set-price offers behave as the demo expects');
