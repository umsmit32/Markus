/*
var line_annotations = null;
var syntax_highlighter_adapter = null;

function sourceCodeReady() {
  syntax_highlighter_adapter = new SyntaxHighlighter1p5Adapter($$('.dp-highlighter').first().getElementsBySelector('ol').first());
  
  //Apply modifications to Syntax Highlighter
  syntax_highlighter_adapter.applyMods();
  
  var collection = new SourceCodeLineArray();
  var line_factory = new SourceCodeLineFactory();
  var line_manager = new SourceCodeLineManager(syntax_highlighter_adapter, line_factory, collection);
  var annotation_text_manager = new AnnotationTextManager();
  var annotation_text_displayer = new AnnotationTextDisplayer($('annotation_holder'));
  
  line_annotations = new SourceCodeLineAnnotations(line_manager, annotation_text_manager, annotation_text_displayer);
}

function add_annotation_text(annotation_text_id, content) {
  var annotation_text = new AnnotationText(annotation_text_id, 0, content);
  line_annotations.registerAnnotationText(annotation_text);
}

function add_annotation(annotation_id, range, annotation_text_id) {
  line_annotations.annotateRange(annotation_id, range, annotation_text_id);
}

function remove_annotation(annotation_id, range, annotation_text_id) {
  line_annotations.removeAnnotationFromRange(annotation_id, range, annotation_text_id);
}

function update_annotation_text(annotation_text_id, new_content) {
  line_annotations.getAnnotationTextManager().getAnnotationText(annotation_text_id).setContent(new_content);
}

function get_mouse_positions() {
 //Get the start (anchor) and finish (focus) text nodes for where the mouse has selected
  var mouse_anchor = get_anchor();
  var mouse_focus = get_focus();
  
  //Use the SourceCodeAdapter to get the nodes that represent source code
  //lines.  
  var anchor_node = syntax_highlighter_adapter.getRootFromSelection(mouse_anchor);
  var focus_node = syntax_highlighter_adapter.getRootFromSelection(mouse_focus);
  
  //Translate these nodes to line numbers
  var line_start = line_annotations.getLineManager().getLineNumber(anchor_node);
  var line_end = line_annotations.getLineManager().getLineNumber(focus_node);

  //If no source code lines were selected, bail out
  if(line_start == 0 && line_end == 0) {
    alert('You must select some source code text');
    return false;
  }
  //If only one valid source code line was selected, we'll only highlight 
  //that one.  This is for the case where you highlight the first line, and
  //then focus some text outside of the source code as well.
  
  if(line_start == 0 && line_end != 0) {
    line_start = line_end;
  }
  if(line_start != 0 && line_end == 0) {
    line_end = line_start;
  }

  //If line_start > line_end, swap
  if(line_start > line_end) {
    var temp = line_start;
    line_start = line_end;
    line_end = temp;
  }
  
  //Return positions as an object
  return {line_start: line_start, line_end: line_end};
}

*/
