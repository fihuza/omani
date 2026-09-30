import QtQuick
import QtTest
import "../.." as Plugin

TestCase {
    id: harness
    name: "AnimeIcon"
    when: windowShown

    Plugin.AnimeIcon {
        id: icon
    }

    function init() {
        failOnWarning(/.*/);
        icon.playing = false;
        icon.iconSize = 16;
    }

    function test_the_glyph_says_whether_something_is_playing() {
        compare(icon.text, icon.pausedGlyph, "a still bar did not show the paused glyph");
        icon.playing = true;
        compare(icon.text, icon.playingGlyph, "a playing episode did not change the glyph");
    }

    function test_the_two_glyphs_are_not_the_same_character() {
        verify(icon.playingGlyph !== icon.pausedGlyph, "both states would look identical in the bar");
        verify(icon.playingGlyph !== "", "the playing glyph is blank");
        verify(icon.pausedGlyph !== "", "the paused glyph is blank");
    }

    function test_the_glyph_is_drawn_at_the_size_it_is_given() {
        icon.iconSize = 24;
        compare(icon.font.pixelSize, 24, "the icon ignored the size the bar asked for");
    }

    function test_the_glyph_is_centred_so_the_bar_slot_holds_it() {
        compare(icon.verticalAlignment, Text.AlignVCenter);
        compare(icon.horizontalAlignment, Text.AlignHCenter);
    }
}
