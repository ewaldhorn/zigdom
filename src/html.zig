const dom = @import("dom.zig");

// ------------------------------------------------------------------------------------------------
// html.zig — Declarative HTML element builder
//
// Provides a chainable builder (`Elm`) and tag constructors so DOM construction
// reads closer to the HTML structure it produces. Zero heap — every element is
// created eagerly on the JS side through the handle table.
//
// Usage:
//   const section = html.div()
//       .class("container")
//       .child(html.h1().text("Hello").build())
//       .child(html.p().class("lead").text("World").build())
//       .appendTo(some_parent_handle)
//       .build();
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
pub const Elm = struct {
    handle: dom.Handle,

    // --------------------------------------------------------------------------------------------
    pub fn init(tag: []const u8) Elm {
        return .{ .handle = dom.createElement(tag) };
    }

    // --------------------------------------------------------------------------------------------
    /// Sets the DOM element id attribute.
    pub fn id(self: *const Elm, val: []const u8) *const Elm {
        dom.set(self.handle, "id", val);
        return self;
    }

    // --------------------------------------------------------------------------------------------
    /// Adds a CSS class — chainable.
    pub fn class(self: *const Elm, val: []const u8) *const Elm {
        dom.addClassTo(self.handle, val);
        return self;
    }

    // --------------------------------------------------------------------------------------------
    /// Sets the inner text content.
    pub fn text(self: *const Elm, val: []const u8) *const Elm {
        dom.setInnerText(self.handle, val);
        return self;
    }

    // --------------------------------------------------------------------------------------------
    /// Sets inner HTML.
    pub fn html(self: *const Elm, val: []const u8) *const Elm {
        dom.setInnerHTML(self.handle, val);
        return self;
    }

    // --------------------------------------------------------------------------------------------
    /// Sets an arbitrary string attribute.
    pub fn attr(self: *const Elm, key: []const u8, val: []const u8) *const Elm {
        dom.set(self.handle, key, val);
        return self;
    }

    // --------------------------------------------------------------------------------------------
    /// Appends a child element (by Handle, typically from `.build()`).
    pub fn child(self: *const Elm, child_handle: dom.Handle) *const Elm {
        dom.addElementTo(self.handle, child_handle);
        return self;
    }

    // --------------------------------------------------------------------------------------------
    /// Appends this element as a child of `parent`.
    pub fn appendTo(self: *const Elm, parent: dom.Handle) *const Elm {
        dom.addElementTo(parent, self.handle);
        return self;
    }

    // --------------------------------------------------------------------------------------------
    /// Adds an event listener.
    pub fn on(self: *const Elm, event: []const u8, cb_id: u32) *const Elm {
        dom.addEventListener(self.handle, event, cb_id);
        return self;
    }

    // --------------------------------------------------------------------------------------------
    /// Returns the underlying Handle — call this to finalise, or read `.handle` directly.
    pub fn build(self: *const Elm) dom.Handle {
        return self.handle;
    }
};

// ------------------------------------------------------------------------------------------------
// Tag constructors
// ------------------------------------------------------------------------------------------------

// -- Structural

pub fn div() Elm      { return Elm.init("div"); }
pub fn span() Elm     { return Elm.init("span"); }
pub fn p() Elm        { return Elm.init("p"); }
pub fn button() Elm   { return Elm.init("button"); }
pub fn a() Elm        { return Elm.init("a"); }

// -- Headings

pub fn h1() Elm       { return Elm.init("h1"); }
pub fn h2() Elm       { return Elm.init("h2"); }
pub fn h3() Elm       { return Elm.init("h3"); }
pub fn h4() Elm       { return Elm.init("h4"); }
pub fn h5() Elm       { return Elm.init("h5"); }
pub fn h6() Elm       { return Elm.init("h6"); }

// -- Semantic

pub fn article() Elm  { return Elm.init("article"); }
pub fn aside() Elm    { return Elm.init("aside"); }
pub fn section() Elm  { return Elm.init("section"); }
pub fn nav() Elm      { return Elm.init("nav"); }
pub fn header() Elm   { return Elm.init("header"); }
pub fn footer() Elm   { return Elm.init("footer"); }
pub fn main_tag() Elm { return Elm.init("main"); } // `main` reserved in Zig

// -- Lists

pub fn ul() Elm       { return Elm.init("ul"); }
pub fn ol() Elm       { return Elm.init("ol"); }
pub fn li() Elm       { return Elm.init("li"); }
pub fn dl() Elm       { return Elm.init("dl"); }
pub fn dt() Elm       { return Elm.init("dt"); }
pub fn dd() Elm       { return Elm.init("dd"); }

// -- Inline text

pub fn strong() Elm   { return Elm.init("strong"); }
pub fn em() Elm       { return Elm.init("em"); }
pub fn code() Elm     { return Elm.init("code"); }
pub fn pre() Elm      { return Elm.init("pre"); }
pub fn small() Elm    { return Elm.init("small"); }
pub fn mark() Elm     { return Elm.init("mark"); }
pub fn b() Elm        { return Elm.init("b"); }
pub fn i() Elm        { return Elm.init("i"); }

// -- Form

pub fn form() Elm     { return Elm.init("form"); }
pub fn input() Elm    { return Elm.init("input"); }
pub fn label() Elm    { return Elm.init("label"); }
pub fn select() Elm   { return Elm.init("select"); }
pub fn option() Elm   { return Elm.init("option"); }
pub fn textarea() Elm { return Elm.init("textarea"); }
pub fn fieldset() Elm { return Elm.init("fieldset"); }
pub fn legend() Elm   { return Elm.init("legend"); }

// -- Media / void

pub fn img() Elm      { return Elm.init("img"); }
pub fn br() Elm       { return Elm.init("br"); }
pub fn hr() Elm       { return Elm.init("hr"); }

// -- Table

pub fn table() Elm    { return Elm.init("table"); }
pub fn thead() Elm    { return Elm.init("thead"); }
pub fn tbody() Elm    { return Elm.init("tbody"); }
pub fn tr() Elm       { return Elm.init("tr"); }
pub fn th() Elm       { return Elm.init("th"); }
pub fn td() Elm       { return Elm.init("td"); }

// -- Misc

pub fn figure() Elm      { return Elm.init("figure"); }
pub fn figcaption() Elm  { return Elm.init("figcaption"); }
pub fn details() Elm     { return Elm.init("details"); }
pub fn summary() Elm     { return Elm.init("summary"); }
pub fn blockquote() Elm  { return Elm.init("blockquote"); }
pub fn cite() Elm        { return Elm.init("cite"); }
pub fn time() Elm        { return Elm.init("time"); }
