xquery version "3.0";

module namespace app = "http://dhil.lib.sfu.ca/exist/wilde/templates";
(:~
 : Main entry points for the app. All templates should call functions in this
 : file only.
 :)
import module namespace templates="http://exist-db.org/xquery/html-templating";
import module namespace lib="http://exist-db.org/xquery/html-templating/lib";

import module namespace functx = "http://www.functx.com";
import module namespace kwic = "http://exist-db.org/xquery/kwic";
import module namespace map = "http://www.w3.org/2005/xpath-functions/map";

import module namespace collection = "http://dhil.lib.sfu.ca/exist/wilde/collection" at "collection.xql";
import module namespace config = "http://dhil.lib.sfu.ca/exist/wilde/config" at "config.xqm";
import module namespace document = "http://dhil.lib.sfu.ca/exist/wilde/document" at "document.xql";
import module namespace graph = "http://dhil.lib.sfu.ca/exist/wilde/graph" at "graph.xql";
import module namespace lang = "http://dhil.lib.sfu.ca/exist/wilde/lang" at "lang.xql";
import module namespace publisher = "http://dhil.lib.sfu.ca/exist/wilde/publisher" at "publisher.xql";
import module namespace similarity = "http://dhil.lib.sfu.ca/exist/wilde/similarity" at "similarity.xql";
import module namespace stats = "http://dhil.lib.sfu.ca/exist/wilde/stats" at "stats.xql";
import module namespace tx = "http://dhil.lib.sfu.ca/exist/wilde/transform" at "transform.xql";

declare namespace array = "http://www.w3.org/2005/xpath-functions/array";
declare namespace string = "java:org.apache.commons.lang3.StringUtils";
declare namespace wilde = "http://dhil.lib.sfu.ca/wilde";
declare namespace xhtml = 'http://www.w3.org/1999/xhtml';

declare default element namespace "http://www.w3.org/1999/xhtml";

(:
    Build a link to a report.
:)
declare function app:link-view($id as xs:string, $content) as node() {
  <a href="view.html?f={$id}">{$content}</a>
};

(:
    Create a table showing some of the reports for navigation.
:)
declare function local:report-table($reports as node()*, $param as xs:string?) as element() {
  let $fields := ('date', 'publisher', 'region', 'city', 'language')[not(. = $param)]
  return
    <table class="table table-striped table-hover table-condensed" id="tbl-browser">
      <thead>
        <tr>
          <th>Headline</th>
          {
            for $field in $fields
            return
              <th>{functx:capitalize-first(local:field2Param($field))}</th>
          }
          <th class="count">Document <br/>Matches</th>
          <th class="count">Paragraph <br/>Matches</th>
          <th class="count">Word Count</th>
        </tr>
      </thead>
      <tbody>{
          for $report in $reports
          return
            <tr>
              <td data-name="Headline">{app:link-view(document:id($report), document:headline($report))}</td>
              {
                for $field in $fields
                return
                  <td data-name="{functx:capitalize-first(local:field2Param($field))}">
                    {app:link-details($report, $field, local:field2Param($field))}
                  </td>
              }
              <td data-name="Document Matches" class="count">{count(document:document-matches($report))}</td>
              <td data-name="Paragraph Matches" class="count">{count(document:paragraph-matches($report))}</td>
              <td data-name="Word Count" class="count">{document:word-count($report)}</td>
            </tr>
        }</tbody>
    </table>
};

(:
    Creates the breadcrumb menu for all pages
:)
declare function app:breadcrumb($node as node(), $model as map(*)) as element()? {
  if (ends-with(request:get-uri(), 'index.html'))
  then
    ()
  else
    let $crumbs := reverse(local:breadcrumb($node, $model))
    return
      <nav aria-label="breadcrumb" class="col-md-12">
        <ol class="breadcrumb">
          <li class="breadcrumb-item"><a href="index.html">Home</a></li>
          {
            for $crumb in $crumbs
            return
              if (functx:index-of-node($crumbs, $crumb) lt count($crumbs))
              then
                <li class="breadcrumb-item">{$crumb}</li>
              else
                <li class="breadcrumb-item active" aria-current="page">{string($crumb)}</li>
          }
        </ol>
      </nav>
};

(:
    Returns the breadcrumb path for a given document. This function determines
    what kind of page we're on and then calls the function associated with that
    page type.
:)
declare function local:breadcrumb($node as node(), $model as map(*)) as item()* {
  let $uri := tokenize(request:get-uri(), '/')[last()]
  return
    (:  Handling for reports: just call local:breadcrumb-report for
        the document :)
    if ($uri = 'view.html')
    then
      let $reportId := request:get-parameter('f', '')
      return
        local:breadcrumb-report(collection:fetch($reportId))
    else
      (: Handling for compare pages, which is a subset of the base 
        document of the comparison (i.e. the "a" report) :)
      if (matches($uri, 'compare(-docs)?.html$'))
      then
        let $compareNode := <span>Compare</span>
        let $reportId := request:get-parameter('a', ())
        return
          ($compareNode, local:breadcrumb-report(collection:fetch($reportId)))
      else
        (: Handling for details pages :)
        if (matches($uri, '-details.html'))
        then
          let $field := substring-before($uri, '-details')
          let $value := request:get-parameter(local:param2Field($field), ())
          return
            local:breadcrumb-details($field, $value)
            
            (: Generic page handling from root :)
        else
          local:breadcrumb-simple($uri, local:get-doc($uri))
};


(:
    Return a breadcrumb path for a report: which is the report
    as link, and then the breadcrumb from the parent newspaper
:)
declare function local:breadcrumb-report($document) {
  let $date := document:date($document)
  let $show := if ($date castable as xs:date)
  then
    format-date($date, '[MNn] [D1], [Y0001]')
  else
    $date
  return
    (app:link-view(document:id($document), $show),
    local:breadcrumb-details('newspaper', document:publisher-id($document), document:publisher($document)))
};


(:
    Return the breadcrumb path for a details page
:)
declare function local:breadcrumb-details($field, $value) {
  let $text := if ($field = 'language') then
    lang:code2lang($value)
  else
    $value
  let $detailsLink := <a href="{$field}-details.html?{local:param2Field($field)}={$value}">{$text}</a>
  let $href := $field || '.html'
  let $doc := local:get-doc($href)
  return
    ($detailsLink, local:breadcrumb-simple($href, $doc))
};

(:
    Return the breadcrumb path for a details page, overriding the text of the link.
:)
declare function local:breadcrumb-details($field, $value, $text) {
  let $detailsLink := <a href="{$field}-details.html?{local:param2Field($field)}={$value}">{$text}</a>
  let $href := $field || '.html'
  let $doc := local:get-doc($href)
  return
    ($detailsLink, local:breadcrumb-simple($href, $doc))
};


(:
    Return the a simple breadcrumb link, which is just the page name
:)
declare function local:breadcrumb-simple($href, $document as node()) {
  <a href="{$href}">{app:page-title($document)}</a>
};

(:
   Function to return a given page's title as encoded in the HTML
   structure
:)

declare function app:page-title($node as node()) as xs:string {
  let $title := $node//h1[1]
  return
    if ($title)
    then
      string($title)
    else
      "No title available"
};



(:
   Retrieves a local document within the application
:)
declare function local:get-doc($path) as document-node()? {
  let $resolved := $config:app-root || '/' || $path
  let $nocache := replace($resolved, '\.html$', '-nocache.html')
  return
    (: Fork depending on whether or not the cached version of the document
            is available :)
    if (doc-available($resolved))
    then
      doc($resolved)
    else
      if (doc-available($nocache))
      then
        doc($nocache)
      else
        ()
};

(:
    Translates a field name (i.e. the metadata field) to
    a parameter. Inverse of local:param2Field
:)
declare function local:field2Param($field as xs:string) as xs:string {
  if ($field = 'publisher') then
    'newspaper'
  else
    $field
};

(:
    Translates a parameter to a parameter (i.e.
    the metadata field). Inverse of local:param2Field
:)
declare function local:param2Field($param as xs:string) as xs:string {
  if ($param = 'newspaper') then
    'publisher'
  else
    $param
};

(:
    Link to a details page ($fn-details.html) based off 
    of a parameter ($param) in a report ($report)
:)

declare function app:link-details($report, $param, $fn) as item()* {
  
  let $lookup := if ($param = 'publisher') then
    'publisher-id'
  else
    $param
    
    (: Construct the function :)
  let $fx := function-lookup(xs:QName('document:' || $lookup), 1)
  
  (: Use the function :)
  let $result := $fx($report)
  
  (: Hook in case we need to clean up the value :)
  let $output :=
  switch ($param)
    case 'language'
      return
        lang:code2lang($result)
    case 'publisher'
      return
        publisher:name($result)
    default return
      $result

  return
    if ($result != '') then
      let $query := request:get-parameter($param, false())
      let $curr := ($query instance of xs:string and $query = $result)
      
      (: If you're the current thing being displayed, don't link :)
      return
        if ($curr) then
          ()
          
          (: Else make a link :)
        else
          <a href="{$fn}-details.html?{$param}={$result}">{$output}</a>
    else
      ()
};


(:
    Count the items in $list that match $item and return the result.
:)
declare function local:count($list, $item) as xs:integer {
  let $matches := for $i in $list
  return
    if ($item = $i) then
      1
    else
      0
  return
    sum($matches)
};

(:
    Build a pagination widget to let users move from one page of results to another.
:)
declare function local:pagination($count as xs:int, $total as xs:int, $query as xs:string) as element()? {
  let $page := request:get-parameter('page', 1) cast as xs:int
  let $span := $config:pagination-window
  let $pageSize := $config:pagination-size
  return
    if ($total > $pageSize) then
      let $pages := xs:integer($total div $pageSize) + 1
      let $start := max((1, $page - $span))
      let $end := min(($pages, $page + $span))
      let $next := min(($pages, $page + 1))
      let $prev := max((1, $page - 1))
      let $isFirstClass := 'first'[xs:integer($page = 1)]
      let $isLastClass := 'last'[xs:integer($page = $pages)]
      return
        <div class="pagination-widget">
          <p>Showing {$count} reports of {$total}.</p>
          
          <nav>
            <ul class="{string-join(('pagination', $isFirstClass, $isLastClass), ' ')}">
              <li><a href="?page=1{$query}">1 ⇐</a></li>
              <li><a href="?page={$prev}{$query}" id='prev-page'>←</a></li>
              {
                for $pn in ($start to $end)
                let $selected := if ($page = $pn) then
                  'active'
                else
                  ''
                return
                  <li class="{$selected}"><a href="?page={$pn}{$query}">{$pn}</a></li>
              }
              <li><a href="?page={$next}{$query}" id='next-page'>→</a></li>
              <li><a href="?page={$pages}{$query}">⇒ {$pages}</a></li>
            </ul>
          </nav>
          <form method='get' class='jump'>
            {
              for $pair in tokenize($query, '&amp;')
                where $pair != ''
              let $parts := tokenize($pair, '=')
              return
                <input type='hidden' name='{$parts[1]}' value='{$parts[2]}'/>
            }
            <input type='number' step="1" name='page' value="" min="1" max="{$pages}" placeholder="Go to page"/>
          </form>
        
        </div>
    else
      ()
};

(:
    Wrapper around local:pagination#3 when there is no query string.
:)
declare function local:pagination($count as xs:int, $total as xs:int) as element()? {
  local:pagination($count, $total, '')
};

(:
    Find a page of reports where the metadata $name has value $content.
:)
declare function local:page($name, $content) {
  let $page := request:get-parameter('page', 1) cast as xs:int
  let $pageSize := $config:pagination-size
  let $documents := collection:documents($name, $content)
  let $total := count($documents)
  
  let $pagination := subsequence($documents, ($page - 1) * $pageSize + 1, $pageSize)
  return
    map {
      "page": $page,
      "count": count($pagination),
      "total": $total,
      "pagination": $pagination
    }
};

(:
    Find a page of reports.
:)
declare function local:page() {
  let $page := request:get-parameter('page', 1) cast as xs:int
  let $pageSize := $config:pagination-size
  let $documents := collection:documents()
  let $total := count($documents)
  
  let $pagination := subsequence($documents, ($page - 1) * $pageSize + 1, $pageSize)
  return
    map {
      "page": $page,
      "count": count($pagination),
      "total": $total,
      "pagination": $pagination
    }
};

(:
    Produce a list of reports.
:)
declare function app:browse($node as node(), $model as map(*)) as node()* {
  let $map := local:page()
  let $widget := local:pagination($map('count'), $map('total'))
  return
    ($widget, local:report-table($map('pagination'), ()), $widget)
};

(:
    Create a map of data for each item in a collection of metadata items
:)
declare function app:browse-items($name as xs:string, $query as xs:string, $page as xs:string) as map(*) {
  let $collection := collection:documents()
  let $metas := $collection//xhtml:meta[@name = $name]
  let $values := $metas/xs:string(@content)
  let $map := map:merge(for $v in distinct-values($values)
  return
    map {$v: local:count($values, $v)})
  let $max := math:log10(max((0,
  for $key in map:keys($map)
  return
    $map($key))))
  return
    map:merge(
    for $key in map:keys($map)
    let $count := $map($key)
    let $percent := (math:log10($count) div $max)
    let $output :=
    switch ($query)
      case 'language'
        return
          lang:code2lang($key)
      case 'publisher'
        return
          publisher:name($key)
      default return
        $key
  let $m := head($metas[@content = $key])
  let $sort := if ($m[@data-sortable]) then
    $m/@data-sortable
  else
    $output
  return
    map {
      $key:
      map {
        'count': $count,
        'percent': $percent,
        'output': $output,
        'query': $query,
        'page': $page,
        'sort': $sort,
        'key': $key
      }
    }
  )
};

(:
    Produce a list from a set of $map of items with an optional
    string to append to the query
:)
declare function app:browse-list($map as map(*), $append as xs:string?) {
  <div class="browse-div">
    <ul class="browse-list">{
        for $key in map:keys($map)
        let $item := map:get($map, $key)
          order by xs:string($item('sort'))
        return
          <li data-count="{$item('count')}" data-value="{$item('output')}" style="--height: {$item('percent') * 100}%" data-region="{$item('region')}">
            <a href="{$item('page')}-details.html?{$item('query')}={$key}{$append}">
              <span class="name">{$item('output')}</span>
              <span class="count">{$item('count')}</span>
            </a>
          </li>
      }
    </ul>
  </div>
};

(:
    Produce browse lists from a set of items, grouped by first letter
:)
declare function app:browse-alphabetize($map as map(*)) as node()+ {
  for $n in (97 to 122)
  return
    let $letter := codepoints-to-string($n)
    let $keys := map:keys($map)[matches(., '^' || $letter, 'i')]
    let $submap := map:merge(for $key in $keys
    return
      map {$key: $map($key)})
    return
      if (exists($keys)) then
        <div class="browse-div alpha-browse-div">
          <h3>{upper-case($letter)}</h3>
          {app:browse-list($submap, ())}
        </div>
      else
        ()
};


(:
    Create a toggle menu for the browse display
:)
declare function app:browse-toggle($defaultName as xs:string) as element()+ {
  <div class="browse-toggle">
    <label for="browse-toggle">Order by</label>
    <select name="browse-toggle" class="form-control">
      <option value="default">{$defaultName}</option>
      <option value="count">Count</option>
    </select>
  </div>
};

(:
    Produce a list of cities and count the reports in that city.
:)
declare function app:browse-city($node as node(), $model as map(*)) as node()+ {
  let $items := app:browse-items('dc.region.city', 'city', 'city')
  return
    <div>
      {app:browse-toggle('Name')}
      {app:browse-alphabetize($items)}
      <script src="resources/js/browse.js"></script>
    </div>
};

(:
    Produce a list of reports in a city.
:)
declare function app:details-city($node as node(), $model as map(*)) as node()* {
  let $city := request:get-parameter('city', false())
  let $map := local:page('dc.region.city', $city)
  let $widget := local:pagination($map('count'), $map('total'), '&amp;city=' || $city)
  return
    ($widget, local:report-table($map('pagination'), 'city'), $widget)
};

(:
    Produce a list of languages used in the reports.
:)
declare function app:browse-language($node as node(), $model as map(*)) as node() {
  let $items := app:browse-items('dc.language', 'language', 'language')
  return
    <div>
      {app:browse-toggle('Language')}
      {app:browse-list($items, ())}
      <script src="resources/js/browse.js"></script>
    </div>
};

(:
    Produce a list of reports in a given language.
:)
declare function app:details-language($node as node(), $model as map(*)) as node()* {
  let $language := request:get-parameter('language', false())
  let $map := local:page('dc.language', $language)
  let $widget := local:pagination($map('count'), $map('total'), '&amp;language=' || $language)
  return
    ($widget, local:report-table($map('pagination'), 'language'), $widget)
};

(:
    Produce a list of newspapers/publishers from the database.
:)
declare function app:browse-newspaper($node as node(), $model as map(*)) as node()+ {
  let $items := app:browse-items('dc.publisher.id', 'publisher', 'newspaper')
  let $keys := map:keys($items)
  return
    <div>
      {app:browse-toggle('Region')}
      {
        for $key in $keys
        let $curr := $items($key)
          group by $region :=
          document:region(collection:documents('dc.publisher.id', $curr('key'))[1])
          order by $region
        return
          let $submap := map:merge(for $k in $key
          return
            map {$k: map:get(map:merge($items), $k)})
          return
            <div class="browse-div">
              <h3>{upper-case($region)}</h3>
              {app:browse-list($submap, ())}
            </div>
      }
      <script src="resources/js/browse.js"></script>
    </div>
};

(:
    Produce a list of reports from a given newspaper/publisher.
:)
declare function app:details-newspaper($node as node(), $model as map(*)) as node()* {
  let $publisher := request:get-parameter('publisher', false())
  let $map := local:page('dc.publisher.id', $publisher)
  let $widget := local:pagination($map('count'), $map('total'), '&amp;publisher=' || $publisher)
  return
    ($widget, local:report-table($map('pagination'), 'publisher'), $widget)
};

(:
    Produce a list of all available regions in the collection
:)
declare function app:browse-region($node as node(), $model as map(*)) as node()+ {
  let $items := app:browse-items('dc.region', 'region', 'region')
  return
    <div>
      {app:browse-toggle('Name')}
      {app:browse-list($items, ())}
      <script src="resources/js/browse.js"></script>
    </div>
};

(:
    Produce a list of reports for a given region
:)
declare function app:details-region($node as node(), $model as map(*)) as node()* {
  let $region := request:get-parameter('region', false())
  let $map := local:page('dc.region', $region)
  let $widget := local:pagination($map('count'), $map('total'), '&amp;region=' || $region)
  return
    ($widget, local:report-table($map('pagination'), 'region'), $widget)
};

(:
    Produce a list of all sources (databases and institutions)
    in the collection
:)
declare function app:browse-source($node as node(), $model as map(*)) as node() {
  let $collection := collection:documents()
  let $dbs := app:browse-items('dc.source.database', 'source', 'source')
  let $institutions := app:browse-items('dc.source.institution', 'source', 'source')
  return
    <div>
      <h2>Databases</h2>
      {
        app:browse-list($dbs, '&amp;type=database')
      }
      <h2>Institutions</h2>
      {
        app:browse-list($institutions, '&amp;type=institution')
      }
    </div>
};

(:
    Produce a list of reports given a source
:)
declare function app:details-source($node as node(), $model as map(*)) as node()* {
  let $source := request:get-parameter('source', false())
  let $type := request:get-parameter('type', 'db')
  let $map := local:page('dc.source.' || $type, $source)
  let $widget := local:pagination($map('count'), $map('total'), '&amp;source=' || $source || '&amp;type=' || $type)
  return
    ($widget, local:report-table($map('pagination'), 'source'), $widget)
};

(:
    Produce a list of all dates available for browsing
:)
declare function app:browse-date($node as node(), $model as map(*)) as node()+ {
  let $collection := collection:documents()
  let $dates := $collection//xhtml:meta[@name = "dc.date"]/string(@content)
  let $calendars := app:browse-calendar($dates)
  let $script := <script src="resources/js/browse.js"></script>
  return
    (app:browse-toggle('Date'), $calendars, $script)
};

(:
    Create a calendar display for a given set of dates
:)
declare function app:browse-calendar($dates as xs:string*) {
  let $jDates := $dates[normalize-space(.) castable as xs:date]
  let $distinctJDates := distinct-values($jDates)
  let $months := distinct-values(for $date in $jDates
  return
    tokenize($date, '-')[2])
  let $header := app:calendar-header()
  for $month in $months
    order by xs:integer($month)
  return
    let $firstDay := xs:date('1895-' || $month || '-01')
    let $offset := app:weekday-from-date($firstDay)
    let $monthLength := app:last-day-of-month($month)
    let $monthName := format-date($firstDay, '[MNn]')
    return
      <div class="browse-div">
        <h2>{$monthName}</h2>
        <div class="calendar offset-{$offset}">
          <div class="cal-header">
            {$header}
          </div>
          <div class="cal-body">{
              for $n in 1 to $monthLength
              let $date := string-join(('1895', $month, format-number($n, '00')), '-')
              let $dateCount := count($dates[matches(., $date)])
              return
                <div class="cal-cell count-{$dateCount}" data-date="{$date}">
                  <a href="date-details.html?date={$date}" data-count="{$dateCount}">
                    <span class="day" data-month="{$monthName}">{$n}</span>
                    <span class="count">{$dateCount}</span>
                  </a>
                </div>
            }</div>
        </div>
      </div>
};

(: 
    Produce the header for a calendar (Sunday start)
:)
declare function app:calendar-header() {
  let $headerDates := (1 to 7) ! format-date(xs:date('2020-03-0' || .), '[FNn]')
  for $date in $headerDates
  return
    <div class="cal-cell">
      <span class="month-text">{$date}</span>
    </div>
};

(:
    Return the last day of some month in 1895 
:)
declare function app:last-day-of-month($month as xs:string) as xs:integer {
  let $one-day := xs:dayTimeDuration('P1D')
  let $one-month := xs:yearMonthDuration('P1M')
  let $month-date := xs:date('1895-' || $month || '-01')
  return
    xs:integer(day-from-date($month-date + $one-month - $one-day))
};

(:
    Return the numerical weekday from a date
:)
declare function app:weekday-from-date($date as xs:date) as xs:integer {
  xs:integer(format-date($date, '[F0]')) + 1
};

(:
    Produce a list of reports for a given date
:)
declare function app:details-date($node as node(), $model as map(*)) as node()* {
  let $date := request:get-parameter('date', false())
  let $map := local:page('dc.date', $date)
  let $widget := local:pagination($map('count'), $map('total'), '&amp;date=' || $date)
  return
    ($widget, local:report-table($map('pagination'), 'date'), $widget)
};

declare function app:parameter($node as node(), $model as map(*), $name as xs:string) as xs:string {
  let $p := request:get-parameter($name, false())
  return
    switch ($name)
      case 'language'
        return
          lang:code2lang($p)
      case 'publisher'
        return
          document:publisher(collection:documents('dc.publisher.id', $p)[1])
      default return
        serialize($p)
};

declare function app:count-documents($node as node(), $model as map(*), $name, $value) as xs:integer {
  if (empty($name) and empty($value)) then
    count(collection:documents())
  else
    count(collection:documents($name, $value))
};

declare function app:load($node as node(), $model as map(*)) {
  let $f := request:get-parameter('f', '')
  let $doc := collection:fetch($f)
  return
    map {
      "doc-id": $f,
      "document": $doc
    }
};

declare function app:doc-title($node as node(), $model as map(*)) as xs:string {
  document:title($model('document'))
};

declare function app:doc-subtitle($node as node(), $model as map(*)) as xs:string {
  document:subtitle($model('document'))
};

declare function app:doc-next($node as node(), $model as map(*)) as node()? {
  let $next := collection:next($model('document'))
  return
    if ($next) then
      <a href="view.html?f={document:id($next)}">{document:title($next)}</a>
    else
      text {"No next document"}
};

declare function app:doc-previous($node as node(), $model as map(*)) as node()? {
  let $previous := collection:previous($model('document'))
  return
    if ($previous) then
      <a href="view.html?f={document:id($previous)}">{document:title($previous)}</a>
    else
      text {"No previous document"}
};

declare function app:doc-word-count($node as node(), $model as map(*)) as xs:string {
  document:word-count($model('document'))
};

declare function app:doc-date($node as node(), $model as map(*)) as element()? {
  app:link-details($model('document'), 'date', 'date')
};

declare function app:doc-updated($node as node(), $model as map(*)) as xs:string {
  document:updated($model('document'))
};

declare function app:doc-publisher($node as node(), $model as map(*)) as element()? {
  app:link-details($model('document'), 'publisher', 'newspaper')

};

declare function app:doc-edition($node as node(), $model as map(*)) as xs:string {
  let $edition := document:edition($model('document'))
  return
    if (string-length($edition) gt 0) then
      " - " || document:edition($model('document'))
    else
      ""
};

declare function app:doc-region($node as node(), $model as map(*)) as xs:string? {
  let $region := app:link-details($model('document'), 'region', 'region') 
  let $city := app:link-details($model('document'), 'city', 'city')
  
  return
    if(not(empty($city))) then
      $region || ", " || $city
    else
      $region
};

declare function app:doc-language($node as node(), $model as map(*)) as element()? {
  app:link-details($model('document'), 'language', 'language')
};

declare function app:doc-translation-tabs($node as node(), $model as map(*)) as node()* {
  <ul class="nav nav-tabs" role="tablist">
    <li role="presentation" class="active">
      <a href="#original" role="tab" data-toggle="tab">
        <b>{lang:code2lang(document:language($model('document')))}</b>
      </a>
    </li>
    {
      for $lang in document:translations($model('document'))
      return
        <li role="presentation">
          <a href="#{$lang}" role="tab" data-toggle="tab">{lang:code2lang($lang)}</a>
        </li>
    }
  </ul>
};

declare function app:doc-translations($node as node(), $model as map(*)) as node()* {
  let $doc := $model('document')
  return
    <div class="tab-content">
      <div role="tabpanel" class="tab-pane active" id="original">
        {tx:document($doc//div[@id = 'original'])}
      </div>
      {
        for $lang in document:translations($model('document'))
        return
          <div role="tabpanel" class="tab-pane" id="{$lang}">
            {tx:document($doc//div[@lang = $lang])}
          </div>
      }
    </div>
};

declare function app:doc-content($node as node(), $model as map(*)) as node()* {
  tx:document($model('document')//body/*)
};

(:
* British Library (dc.source.institution if present)
* British Library Newspapers (dc.source.database if present)
* explore.bl.uk (the name part of dc.source.url, if present. Linked to the complete URL. May be repeated.)
:)
declare function app:doc-source($node as node(), $model as map(*)) as node()* {
  (
  for $institution in document:source-institution($model('document'))
  return
    <dd>{$institution}</dd>
  ),
  (
  for $database in document:source-database($model('document'))
  return
    <dd>{$database}</dd>
  ),
  (
  for $url in document:source-url($model('document'))
  return
    <dd>
      <a href="{$url}" target="_blank">
        {
          analyze-string($url, '^https?://([^/]*)')//fn:group[@nr = 1]/string(.)
        }
      </a>
    </dd>
  )
};

declare function app:doc-facsimile($node as node(), $model as map(*)) as node()* {
  let $urls := document:facsimile($model('document'))
  return
    if (not(empty($urls))) then
      for $url in $urls
      return
        <dd>
          <a href="{$url}" target="_blank">
            {
              analyze-string($url, '^https?://([^/]*)')//fn:group[@nr = 1]/string(.)
            }
          </a>
        </dd>
    else
      <dd> {
        if(request:get-parameter('f', '') != '') then
          <i>None found</i>
        else 
          ''
        }
      </dd>
};

declare function app:document-indexed($node as node(), $model as map(*)) as xs:string {
  document:indexed-document($model('document'))
};

declare function app:paragraph-indexed($node as node(), $model as map(*)) as xs:string {
  document:indexed-paragraph($model('document'))
};

declare function app:document-similarities($node as node(), $model as map(*)) as node()* {
  let $similarities := document:similar-documents($model('document'))
  let $levens := $similarities[@data-type = 'lev']
  let $exact := $similarities[@data-type = 'exact']
  
  return
    if (count($similarities) = 0) then
      (<i>None found</i>)
    else
      <div>
        <div class='panel-body'>{
            if (count($levens) = 0) then
              <i>None found</i>
            else
              <ul>
                {
                  for $link in $levens
                  let $doc := collection:fetch($link/@href)
                    order by $link/@data-similarity descending
                  return
                    <li class="{$link/@class}">
                      {app:link-view($link/@href, document:title($doc))} - {format-number($link/@data-similarity, "###.#%")} <br/>
                      <a href='compare-docs.html?a={document:id($model('document'))}&amp;b={document:id($doc)}'>Compare</a>
                    </li>
                }
              </ul>
          }</div>
      </div>
};

declare function app:paragraph-similarities($node as node(), $model as map(*)) as node()* {
  let $similarities := document:similar-paragraphs($model('document'))
  return
    if (count($similarities) = 0) then
      ()
    else
      <ul>
        {
          for $link in $similarities
          let $doc := collection:fetch($link/@data-document)
          return
            <li class="{$link/@class}">
              {app:link-view($link/@data-document, document:title($doc))} ({format-number($link/@data-similarity, "###.#%")})
            </li>
        }
      </ul>
};

declare function app:search($node as node(), $model as map(*)) {
  let $query := request:get-parameter('query', '')
  let $page := request:get-parameter('p', 1)
  let $options := map {
    "facets": map {
      "lang": request:get-parameter('facet-lang', ()),
      "region": request:get-parameter('facet-region', ()),
      "publisher": request:get-parameter('facet-publisher', ())
    }
  }
  
  let $hits := collection:search($query, $options)
  
  let $facets := map {
    'lang': ft:facets($hits, "lang"),
    'region': ft:facets($hits, "region"),
    'publisher': ft:facets($hits, "publisher")
  } 
  
  return
    map {
      'hits': $hits,
      'query': $query,
      'page': $page,
      'facets': $facets,
      'options': $options
    }
};

declare function app:search-facets($node as node(), $model as map(*)) {
  if($model('query') = '') then
    ()
  else
    let $options := $model('options')('facets')
    let $facets := $model('facets')
    let $languages := 
      for $code in $options('lang')
      return lang:code2lang($code)
  
    return 
      <div>
      <h3>Filters</h3>
      <div class='btn-group'>
      <button id='apply' type='submit' class='btn btn-primary'>Apply</button>
      <button id='clear' type='submit' class='btn btn-primary'>Clear</button>
      </div>
      
      <div class='panel panel-default'> 
        <div class='panel-heading'>Language</div>
        <div class='panel-body panel-facet'> {
          for $code in map:keys($facets('lang'))
            let $label := lang:code2lang($code)
            let $checked := index-of($options('lang'), $code) gt 0
            order by $label
            return 
              <label class='facet'>
                <input type="checkbox" value="{$code}" name="facet-lang" class='facet'>
                  { if ($checked) then attribute checked { '' } else () }
                </input>
                {$label}: {$facets('lang')($code)}
              </label>
        } </div>
      </div>
  
      <div class='panel panel-default'> 
        <div class='panel-heading'>Publisher</div>
          <div class='panel-body panel-facet'> {
          for $publisher in map:keys($facets('publisher'))
            order by $publisher
            return 
              <label class='facet'>
                <input type="checkbox" value="{$publisher}" name="facet-publisher" class='facet'>
                  { if(index-of($options('publisher'), $publisher) gt 0) then attribute checked {''} else () }
                </input>
                {$publisher}: {$facets('publisher')($publisher)}
              </label>
        } </div>
      </div>
  
      <div class='panel panel-default'> 
        <div class='panel-heading'>Region</div>
        <div class='panel-body panel-facet'> {
          for $region in map:keys($facets('region'))
            order by $region
            return 
              <label class='facet'><input type="checkbox" value="{$region}" name="facet-region" class='facet'>
                  { if(index-of($options('region'), $region) gt 0) then attribute checked {''} else () }
                </input>
                {$region}: {$facets('region')($region)}
              </label>
        } </div>
      </div>
    </div>
};

declare function app:search-summary($node as node(), $model as map(*)) {
  if (empty($model('query')) or $model('query') = '') then
    ()
  else
    <p>
      Found {count($model('hits'))} matching reports for search
      query <kbd>{$model('query')}</kbd>.
    </p>
};

declare function app:search-export($node as node(), $model as map(*)) {
  let $query := request:get-parameter('query', false())
  
  return
    if ($query) then
      <button id='export' type='submit' class='btn btn-primary'>Export Results</button>
    else
      ()
};

declare function app:search-paginate($node as node(), $model as map(*)) {
  let $query := $model('query')
  let $page := $model('page') cast as xs:integer
  let $span := 3
  let $hit-count := count($model('hits')) cast as xs:integer
  let $pages := xs:integer($hit-count div $config:search-results-per-page) + 1
  let $start := max((1, $page - $span))
  let $end := min(($pages, $page + $span))
  let $next := min(($pages, $page + 1))
  let $prev := max((1, $page - 1))
  
  return
    if ($hit-count <= $config:search-results-per-page) then
      ()
    else
      <nav>
        <ul class='pagination'>
          <li><a href="?query={$query}&amp;p=1">⇐</a></li>
          <li><a href="?query={$query}&amp;p={$prev}" id='prev-page'>←</a></li>
          
          {
            for $pn in ($start to $end)
            let $selected := if ($page = $pn) then
              'active'
            else
              ''
            return
              <li class="{$selected}"><a href="?query={$query}&amp;p={$pn}">{$pn}</a></li>
          }
          
          <li><a href="?query={$query}&amp;p={$next}" id='next-page'>→</a></li>
          <li><a href="?query={$query}&amp;p={$pages}">⇒</a></li>
        </ul>
      </nav>
};

declare function app:search-results($node as node(), $model as map(*)) {
  if (empty($model('query'))) then
    ()
  else
    let $page := $model('page') cast as xs:integer - 1
    let $offset := $page * $config:search-results-per-page + 1
    let $hits := subsequence($model('hits'), $offset, $config:search-results-per-page)
    
    return
      for $hit at $p in $hits
      let $did := document:id($hit)
      let $pid := string($hit/@id)
      let $title := document:title($hit)
      let $config := <config xmlns='' width="60" table="no"
        link="view.html?f={$did}&amp;query={$model('query')}#{$pid}"/>
      return
        (<p><a href="view.html?f={$did}&amp;query={$model('query')}"><b>{$title}</b></a></p>, kwic:summarize($hit, $config))
};

declare function local:find-similar($measure as xs:string, $p as node()*, $q as node()) {
  let $matches :=
  for $t in $p
  let $score := similarity:similarity($measure, $t, $q)
    where $score > 0
    order by $score descending
  return
    <div data-similarity="{$score}">{$t}</div>
  return
    $matches[1]
};

declare function app:compare-paragraphs($node as node(), $model as map(*)) {
  let $a := request:get-parameter('a', '')
  let $b := request:get-parameter('b', '')
  
  let $da := collection:fetch($a)
  let $db := collection:fetch($b)
  
  let $lang := $da//div[@id = 'original']/@lang
  
  let $pa := $da//div[@id = 'original']//p[not(@class = 'heading')]
  let $pb := $db//div[@id = 'original']//p[not(@class = 'heading')]
  
  let $la := app:link-view($a, document:title($da))
  let $lb := app:link-view($b, document:title($db))
  
  return
    <div>
      <div class="row compare-header">
        <div class='col-sm-4'>
          <b>Original paragraph in <br/>
            {$la}</b>
        </div>
        <div class='col-sm-4'>
          <b>Most similar paragraph from <br/>
            {$lb}</b>
        </div>
        <div class='col-sm-4'>
          <b>Difference</b>
        </div>
      </div>
      {
        for $other at $i in $pa
          let $q := local:find-similar("levenshtein", $pb, $other)
          let $n := $q//a[@data-paragraph = $other/@id]/@data-similarity
          let $similarity := if ($n) then
            format-number($n cast as xs:float, "###.#%")
          else
            ""
          
          return
            <div class='row paragraph-compare' data-score="{$similarity}%">
              <div class="col-sm-4 paragraph-a">
                <div class="compare-link">{$la}</div>
                <div class='content'>{string($other)}</div>
              </div>
              <div class="col-sm-4 paragraph-b">
                <div class="compare-link">{$lb}</div>
                {
                  if ($q) then
                    <div class='content'>{string($q)}</div>
                  else
                    '—'
                }
              </div>
              <div class="col-sm-4 paragraph-d" data-caption="Difference">
              </div>
          </div>
      }
    </div>
};

declare function local:measure($name as xs:string) as xs:string {
  switch ($name)
    case 'lev'
      return
        'Levenshtein'
    case 'cos'
      return
        'Cosine'
    case 'exact'
      return
        'Exact'
    default return
      'Unknown'
};

declare function app:compare-documents($node as node(), $model as map(*)) {
  let $a := request:get-parameter('a', '')
  let $b := request:get-parameter('b', '')
  
  let $da := collection:fetch($a)
  let $db := collection:fetch($b)
  
  let $da-title := document:title($da)
  let $db-title := document:title($db)
  
  let $lang := $da//div[@id = 'original']/@lang
  
  let $pa := $da//div[@id = 'original']//p[not(@class = 'heading')]
  let $pb := $db//div[@id = 'original']//p[not(@class = 'heading')]
  let $links := $da//link[@href = $b]
  
  return
    (app:compare-documents-nav($da-title, $db-title),
    <div class="doc-compare">
      <div class="compare-col" id="col1">
        <h3>{app:link-view($a, $da-title)}</h3>
        <div id="doc_a">{
            for $p in $pa
            return
              <p>{$p/text()}</p>
          }
        </div>
      </div>
      <div class="compare-col" id="col2">
        <h3>{app:link-view($b, $db-title)}</h3>
        <div id="doc_b">
          {
            for $p in $pb
            return
              <p>{$p/text()}</p>
          }
        </div>
      </div>
      <div id="col3">
        <h3>
          <span>Highlighted Differences</span>
          {
            if (count($links) gt 0) then
              for $link in $links
              return
                <span style="display:block;">Match: {format-number($link/@data-similarity, "###.#%")}</span>
            else
              <span style="display:block">Not significantly similar</span>
          }
        </h3>
        <div id="diff"></div>
      </div>
    </div>)
};

declare function app:compare-documents-nav($da-title as xs:string, $db-title as xs:string) as element()* {
  <nav class="doc-compare-nav">
    <ul class="list-inline">
      <li>
        <a href="#col1">
          <span class="sr-only">Go to {$da-title}</span>
        </a>
      </li>
      <li>
        <a href="#col2">
          <span class="sr-only">Go to {$db-title}</span>
        </a>
      </li>
      <li>
        <a href="#col3">
          <span class="sr-only">Go to comparison</span>
        </a>
      </li>
    </ul>
  </nav>
};

declare function app:similarities-summary($node as node(), $model as map(*)) {
  <p>Found {count($model('similarities'))} similarities in the collection of reports.</p>
};

declare function app:similarities-paginate($node as node(), $model as map(*)) {
  let $page := $model('page') cast as xs:integer
  let $span := 3
  let $hit-count := count($model('similarities')) cast as xs:integer
  let $pages := xs:integer($hit-count div $config:similarities-per-page) + 1
  let $start := max((1, $page - $span))
  let $end := min(($pages, $page + $span))
  let $next := min(($pages, $page + 1))
  let $prev := max((1, $page - 1))
  
  return
    <nav>
      <ul class='pagination'>
        <li><a href="?p=1">⇐</a></li>
        <li><a href="?p={$prev}" id='prev-page'>←</a></li>
        
        {
          for $pn in ($start to $end)
          let $selected := if ($page = $pn) then
            'active'
          else
            ''
          return
            <li class="{$selected}"><a href="?p={$pn}">{$pn}</a></li>
        }
        
        <li><a href="?p={$next}" id='next-page'>→</a></li>
        <li><a href="?p={$pages}">⇒</a></li>
      </ul>
    </nav>
};

declare function app:similarities-results($node as node(), $model as map(*)) {
  let $page := $model('page') cast as xs:integer - 1
  let $offset := $page * $config:search-results-per-page + 1
  
  let $hits := subsequence($model('similarities'), $offset, $config:search-results-per-page)
  
  return
    <div>
      <div class='rowparagraph-compare'>
        <div class='col-sm-4'>
          Earlier
        </div>
        <div class='col-sm-4'>
          Later (or same date)
        </div>
        <div class='col-sm-4'>Difference</div>
      </div>
      {
        for $a in $hits
        let $pa := $a/ancestor::p
        let $pb := collection:paragraph($a/@data-document, $a/@data-paragraph)
        return
          <div>
            <div class='rowparagraph-head'>
              <div class='col-sm-4'>
                {app:link-view(document:id($pa), <strong>{document:title($pa)}</strong>)}
              </div>
              <div class='col-sm-4'>
                {app:link-view(document:id($pb), <strong>{document:title($pb)}</strong>)}
              </div>
              <div class='col-sm-4'>
                <strong>difference</strong>
              </div>
            </div>
            <div class='rowparagraph-compare' data-score="{format-number($a/@data-similarity, "###.#%")}">
              <div class='col-sm-4paragraph-a'>
                {string($pa)}
              </div>
              <div class='col-sm-4paragraph-b'>
                {string($pb)}
              </div>
              <div class='col-sm-4paragraph-d'>
              </div>
            </div>
          </div>
      }
    </div>

};

declare
%templates:wrap
function app:measure-textarea($node as node(), $model as map(*), $name) {
  request:get-parameter($name, '')
};

declare function app:statistics($node as node(), $model as map(*)) {
  <dl>
    <dt>Word count</dt>
    <dd>{stats:count-words()}</dd>
    <dt>Paragraph count</dt>
    <dd>{stats:count-paragraphs()}</dd>
    <dt>Document count</dt>
    <dd>{stats:count-documents()}</dd>
    <dt>Paragraphs with one or more matches</dt>
    <dd>{stats:count-paragraphs-with-matches()}</dd>
    <dt>Total paragraph matches</dt>
    <dd>{stats:count-paragraph-matches()}</dd>
    <dt>Documents with one or more matches</dt>
    <dd>{stats:count-documents-with-matches()}</dd>
    <dt>Total document matches</dt>
    <dd>{stats:count-document-matches()}</dd>
  </dl>
};

declare function app:graph-list($node as node(), $model as map(*)) as node() {
  <dl>{
      for $graph in collection:graph-list()
      return
        (
        <dt><a href="graph.html?f={graph:filename($graph)}">{graph:title($graph)}</a></dt>,
        <dd>
          {graph:description($graph)}<br/>
          {graph:modified($graph)}
        </dd>
        )
    }</dl>
};

declare function app:load-graph($node as node(), $model as map(*)) {
  let $f := request:get-parameter('f', '')
  let $doc := collection:graph($f)
  
  return
    map {
      "graph-id": $f,
      "graph": $doc
    }
};

declare function app:graph-view($node as node(), $model as map(*)) as node() {
  let $f := request:get-parameter('f', '')
  return
    <iframe src="gefx.html#{$f}" style="width: 100%; height: 700px;"/>
};

(:
    Produce the gallery of images
:)
declare function app:gallery($node as node(), $model as map(*)) as node() {
  let $filenames := collection:image-list()
  let $cols := 3
  let $empty := count($filenames) mod $cols
  let $metadata := collection:image-meta()
  let $tileCount := count($filenames) + $empty
  return
    <div class="gallery">{
        for $index in 1 to $tileCount
        return
          if ($index <= count($filenames)) then
            let $filename := $filenames[$index]
            let $meta := $metadata//div[@data-filename = $filename]
            return
              app:gallery-tile($filename, $meta)
          else
            <div class="img-tile empty">
            </div>
      }
    </div>
};

(:
    Create an image tile from a $filename
:)
declare function app:gallery-tile($filename as xs:string, $meta as node()?) {
  let $title := if ($meta) then
    $meta/@data-title/string()
  else
    ""
  let $date := if ($meta) then
    $meta/@data-date/string()
  else
    ""
  let $descr := if ($meta/node()/text()) then
    $meta/node()
  else
    <p>{$filename}</p>
  return
    <div class="img-tile">
      <div class="thumbnail">
        <div class="img-container">
          <a href="#imgModal" data-toggle="modal" data-title="{$title}" data-date="{$date}" data-target="#imgModal" data-img="images/{$filename}">
            <img alt="{normalize-space(string-join($meta, ''))}" src="thumbs/{$filename}" class="img-thumbnail"/>
          </a>
        </div>
        <div class="caption">
          <div class="title"><i>{$title}</i><br/>{$date}<br/></div>
          {$descr}
        </div>
      </div>
    </div>
};

(: Create TOC for the documentation :)
declare function app:toc($node as node(), $model as map(*)) {
  let $divs := root($node)//div[@id = 'article']/div[@id and child::*[matches(local-name(), '^h\d+')]]
  return
    app:toc-list($divs)
};

declare function app:toc-list($divs) {
  if (exists($divs)) then
    <ul>
      {$divs ! app:toc-item(.)}
    </ul>
  else
    ()
};

declare function app:toc-item($div) {
  let $id := $div/@id
  let $label := string($div/child::*[matches(local-name(), '^h\d+')])
  let $children := $div/div[@id and child::*[matches(local-name(), '^h\d+')]]
  return
    <li>
      <a href="#{$id}">{$label}</a>
      {app:toc-list($children)}
    </li>
};
