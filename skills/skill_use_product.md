# Product Test Drive Skill

Use this when the user asks the agent to try a product in the real wkdomains browser, especially when the active tab is already logged into an app.

## Goal

Act like a serious first-time user. First understand the public website promise, then use the logged-in product enough to verify whether the app delivers that promise. Do not record video or generate voice unless the user explicitly asks for it.

## Browser API

Use the wkdomains local browser API:

```sh
curl -sS http://localhost:9001/api/v1/page | jq .
curl -sS http://localhost:9001/api/v1/dom | jq .
curl -sS http://localhost:9001/api/v1/snapshot | jq .
curl -sS http://localhost:9001/api/v1/console | jq .
curl -sS http://localhost:9001/api/v1/xhr | jq .
```

Navigate with:

```sh
curl -sS -X POST http://localhost:9001/api/v1/navigate \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com/","mode":"hard"}' | jq .
```

Interact with:

```sh
curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"click","ref":"@e1"}' | jq .

curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"fill","ref":"@e2","value":"Example value"}' | jq .
```

## Test Drive Flow

1. Confirm the active page and logged-in state.
2. Visit the public marketing site for 3 to 5 minutes.
3. Extract the product promise: category, target customer, core workflow, pricing model, and claims.
4. Return to the logged-in app.
5. Find the most important empty-state CTA and start there.
6. Create realistic test data that fits the product promise.
7. Push through validation errors and hidden controls.
8. Continue until a user-facing artifact exists, such as a published product, checkout link, report, project, or generated output.
9. Inspect the customer/user-facing result, but do not purchase, send messages, or trigger irreversible external effects unless the user explicitly asked.
10. Check console and XHR for obvious errors.
11. Update this skill with product-specific gotchas and reusable steps.

## Kelviq Notes

Public positioning from `https://www.kelviq.com/`:

- Kelviq presents itself as software monetization infrastructure for SaaS and AI companies.
- Core promise: payments, usage billing, tax/Merchant of Record, entitlements, checkout, customer portal, and SDKs in one system.
- Strongest app test path: create product -> create plan -> configure price -> add feature entitlement -> publish -> generate checkout link -> inspect checkout page.

Successful Kelviq test data:

```text
Product name: AI Token Metering Starter Kit
Product identifier: ai-token-metering-starter-kit
Product type: SaaS (Business / B2B)
Product description: A test product for validating Kelviq usage billing, checkout, and entitlement workflows for an AI SaaS that meters token consumption.

Plan name: Pro Token Metering
Plan identifier: pro-token-metering
Plan description: For teams that need token metering, usage limits, and customer-facing checkout for an AI SaaS.
Monthly price: 49
Yearly price: 499

Feature name: Monthly AI token quota
Feature identifier: monthly-ai-token-quota
Feature description: Allows customers on this plan to consume AI tokens up to the configured monthly entitlement limit.
```

Kelviq flow findings:

- `Create product` opens a modal with required product name, identifier, and product type.
- The cover-image section starts expanded and can hide the lower form controls in a narrow desktop viewport. Collapse `Cover image` to expose Description, Cancel, and Create.
- Rich text descriptions may use `.ProseMirror`; fill with selector `.ProseMirror` when no textbox ref appears.
- Creating a product opens a product detail page with an empty-state `Create plan` CTA.
- Plan creation requires plan name and identifier; description is optional but useful for checkout copy.
- The pricing editor has a `Free plan` switch. When it is active, it hides monthly/yearly amount fields. If the goal is paid pricing, make sure paid fields are visible before filling prices.
- On narrow desktop, controls such as `Get Link` and `Publish` may be off to the right. Use horizontal scroll if the DOM text mentions them but snapshot/action query cannot see them:

```sh
curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"scroll","direction":"right","amount":350,"durationMs":400}' | jq .
```

- If a Save button is outside the current viewport, a selector click can still work:

```sh
curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"click","selector":"form button[type=submit]"}' | jq .
```

- `Get Link` before publishing shows: `No published plans Only published plans are available for checkout links.`
- Publishing opens a confirmation dialog: `Publish plan? Your plan will be published and visible to customers.`
- After publishing, `Get Link` opens a checkout-link generator with monthly/yearly options, optional discounts, and a generated checkout URL.
- The generated checkout page showed the product, plan descriptions, monthly/yearly prices, and included feature entitlement.
- Customer checkout fields observed: full name, business purchase checkbox, country/region, ZIP code, discount code, and Pay Now.
- Stop before clicking `Pay Now` unless the user explicitly asks to test payment behavior.

Kelviq observations from this pass:

- The happy path works: product, paid plan, boolean entitlement, publish, and checkout page were all created successfully.
- Entitlements are concrete in-app: the checkout page displayed `Monthly AI token quota Included`.
- The SDK snippet in the entitlements area is useful because it connects dashboard setup to implementation.
- Some controls are hard for an agent in a narrow viewport because the app can create horizontal scrolling. Re-check `scrollX` and use horizontal scroll when a visible-text item is not in the snapshot.
- Feature type selection was unclear through the automation snapshot. It defaulted to `Switch/boolean`; investigate feature-type options in a future pass if usage quotas need numeric limits rather than enabled/disabled access.
- License keys were disabled in this scenario, likely because the current product/plan setup did not meet its prerequisites.
- Business verification remains prominent through `Add details`, but publishing a test plan and generating a checkout URL still worked.

## Product Review Notes

When reporting back, separate:

- What the marketing site promised.
- What the app actually allowed.
- What was successfully created.
- What blocked or confused the flow.
- What should be tested next.

Avoid overclaiming. If a workflow was visible but not completed, say that clearly.
