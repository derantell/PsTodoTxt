$todoFile = "E:\CloudStorage\Dropbox\todo\todo.txt"
$doneFile = "E:\CloudStorage\Dropbox\todo\done.txt"

$opt = [System.Text.Regularexpressions.RegexOptions]
$linePattern = @"
    ^(?:x\ (?<done>\d{4}-\d{2}-\d{2})\ )?  # Done date
     (?:\((?<prio>[A-Z])\)\ )?             # Priority
     (?:(?<created>\d{4}-\d{2}-\d{2})?\ )? # Created date
     (?<task>.*)
    $
"@

$usage = @"
Usage: t command [options]

Commands:

a[dd]       Adds a new todo item to the list
    Ex:     t a "(A) my new task"

d[one]      Marks the specified todo items as done
    Ex:     t d 3,5,8

l[ist]      Lists all todo items in prio order
    Ex:     t l "@context +project"

p[rio]      Sets the priority of a todo item
    Ex:     t p 2,C

r[emove]    Removes the specified todo items
    Ex:     t r 1,4,10

u[pdate]    Updates the specified todo item
    Ex:     t u 2, "My updated task"

h[elp]      Displays this help message
    Ex:     t h

"@

$todoPattern = New-Object System.Text.Regularexpressions.Regex($linePattern, $opt::IgnorePatternWhitespace)

Function Use-TodoTxt {
    [CmdletBinding(SupportsShouldProcess=$False, ConfirmImpact="Low")]
    Param(
        [string] 
        $command,

        [string[]]
        $params = @('')
    )              

    switch -regex ($command){
        #list
        "\bli?s?t?\b|^$" {
            $todos = @(Get-TodoTxt | Where-TodoTxt -filter $params[0])

            Write-Host
            Write-Host "Todo.txt file: $todoFile"
            Write-Host "---"

            $todos `
                | Sort-Object DoneDate, @{Expression={if($_.Prio -eq '') {'ZZ'} else {$_.Prio}}}, LineNo `
                | Write-TodoTxt

            Write-Host "---"
            Write-Host ("TODO: {0} tasks" -f $todos.Count) -nonewline
            if ($params[0].length -gt 0) {
                Write-Host (" containing terms {0}" -f $params[0]) -nonewline
            } 
            Write-Host
            Write-Host
        }
        #add
        "\bad?d?\b"   {Add-TodoTxt -text $params[0]}
        #done
        "\bdo?n?e?\b" { Set-TodoTxtDone -lines $params }
        #prio
        "\bpr?i?o?\b" { Set-TodoTxtPrio -line $params[0] -prio $params[1]}
        #remove
        "\bre?m?o?v?e?\b" { Remove-TodoTxt -line $params[0] }
        #update
        "\bup?d?a?t?e?\b" { Set-TodoTxtTask -line $params[0] -task $params[1] }

        default { $usage }
    }    
}


Function Set-TodoTxtTask($line, $task) {
    $todos = Get-TodoTxt

    $todo = $todos | ?{$_.LineNo -eq $line}

    if(!$todo) {"No todo item #$line"; return}
    
    $todo.Task = $task
    $todo.Canonical = Format-TodoTxt $todo

    $todos | %{$_.Canonical} | Set-Content -path $todoFile -encoding utf8
}


Function Remove-TodoTxt( $line ) {
    $todos = Get-TodoTxt

    $doneTask = $todos | ?{$_.LineNo -eq $line}

    if(!$doneTask) {"No task #$line"; return}

    $todos | ?{$_.LineNo -ne $line} | %{$_.Canonical} | Set-Content -path $todoFile -encoding utf8    
}


Function Set-TodoTxtPrio( $line, $prio = '-' ) {
    $todos = Get-TodoTxt

    $task = $todos | ?{$_.LineNo -eq $line} 

    if(!$task) {"No task #$line"; return}
    if($prio -notmatch '^[A-Z-]$') {"Invalid prio: $prio. Use A-Z or - to clear"; return}

    $task.Prio = if($prio -ne '-') {$prio} else {''}
    $task.Canonical = Format-TodoTxt $task

    $todos | %{$_.Canonical} | Set-Content -path $todoFile -encoding utf8
}

Function Format-TodoTxt($todo) {    
    $donePart = Format-PartOrEmpty $todo.DoneDate "x {0}"
    $prioPart = Format-PartOrEmpty $todo.Prio "({0})"
    (@($donePart, $prioPart, $todo.CreatedDate, $todo.Task) | Where-Object {$_ -ne ''}) -join ' '
}

function Format-PartOrEmpty($part, $fmt) {
    if($part -ne '') { $fmt -f $part } else { '' }    
}

Function Set-TodoTxtDone( $lines ) {
    $todos = Get-TodoTxt

    $doneTasks = $todos | ?{$lines -contains $_.LineNo}

    if(!$doneTasks) {"No tasks # $lines"; return}

    $today = Get-Date -f "yyyy-MM-dd"
    $doneTasks | %{ "x $today $($_.Canonical)" } | Add-Content -path $doneFile -encoding utf8
    $todos | ?{$lines -notcontains $_.LineNo } | %{$_.Canonical} | Set-Content -path $todoFile -encoding utf8
}

Function Where-TodoTxt {
    Param(
        [Parameter(Mandatory=$True, ValueFromPipeline=$True)]
        $todoTxt,

        [String]
        $filter = ''
    )

    BEGIN {
        $terms = @($filter.Split(' ',[StringSplitOptions]'RemoveEmptyEntries'))
    }

    PROCESS {                
        if( $terms.Count -eq 0 ) {
            Write-Output $todoTxt; return
        }

        $tokens = $todoTxt.Task.Split(' ')

        $matchingTokens = @($tokens | ?{$terms -contains $_} | Get-Unique)

        if( $matchingTokens.Count -ge $terms.Count) {
            Write-Output $todoTxt
        }
    }    
}


Function Write-TodoTxt {
    Param(
        [Parameter(Mandatory=$True, ValueFromPipeline=$True)]
        $todoTxt
    )

    PROCESS {
        $text = "{0,3}: {1}" -f $todoTxt.LineNo, $todoTxt.Canonical
        $rowColor, $contextColor, $projectColor = 'blue', 'green', 'magenta'
        
        if ($todoTxt.DoneDate -ne '') {
            $rowColor = 'DarkGray'
        } else {
            switch ($todoTxt.Prio) {
                'A' { $rowColor = 'DarkRed' }
                'B' { $rowColor = 'DarkYellow' }
                'C' { $rowColor = 'Yellow' }                
            }    
        }

        $text.Split(' ') | %{
            if($_.StartsWith('@')) {Write-Host $_ -ForegroundColor $contextColor -nonewline}
            elseif($_.StartsWith('+')) {Write-Host $_ -ForegroundColor $projectColor -nonewline}
            else {Write-Host $_ -ForegroundColor $rowColor -nonewline}
            Write-Host ' ' -nonewline
        }

        Write-Host
    }
}


Function Get-TodoTxt {
    $todos = Get-Content $todoFile -encoding utf8
    
    $i = 0
    foreach ($todo in $todos) {
        $i++
        
        $parsedLine = $todoPattern.Match($todo).Groups

        $todoObj = New-Object PSObject -Property @{
            Task        = $parsedLine['task'].Value
            DoneDate    = $parsedLine['done'].Value
            CreatedDate = $parsedLine['created'].Value
            Prio        = $parsedLine['prio'].Value
            Canonical   = $todo
            LineNo      = $i
        }

        Write-Output $todoObj
    }
}


Function Add-TodoTxt($text) {
    $today = Get-Date -f "yyyy-MM-dd"
    $words = @($text.Split(' '))
    $first, $rest = $words
    
    if($first -match '\([A-Z]\)') {    
        $task = @($first, $today) + $rest -join ' '
    } else {        
        $task = "$today $text"
    }

    Add-Content -path $todoFile -value $task -encoding utf8
}

Set-Alias t Use-TodoTxt

Export-ModuleMember -Function Use-TodoTxt, Get-TodoTxt -Alias t