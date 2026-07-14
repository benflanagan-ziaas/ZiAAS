#requires -version 5.1
<##
ZiAAS Woodstock Baselining GUI example.

This is a non-destructive visual prototype. It demonstrates the branded operator
experience that can sit in front of the existing PowerShell orchestrator. It does
not uninstall or install software.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ZiAAS Woodstock Baselining"
        Width="1180" Height="760" MinWidth="980" MinHeight="650"
        WindowStartupLocation="CenterScreen"
        Background="#F4F7FA"
        FontFamily="Segoe UI"
        FontSize="14">
  <Window.Resources>
    <SolidColorBrush x:Key="Navy" Color="#10243E" />
    <SolidColorBrush x:Key="Blue" Color="#1F3A5F" />
    <SolidColorBrush x:Key="Cyan" Color="#18A7C8" />
    <SolidColorBrush x:Key="Green" Color="#168A5B" />
    <SolidColorBrush x:Key="Amber" Color="#B7791F" />
    <SolidColorBrush x:Key="Red" Color="#B42318" />
    <SolidColorBrush x:Key="Ink" Color="#142033" />
    <SolidColorBrush x:Key="Muted" Color="#5B677A" />
    <SolidColorBrush x:Key="Line" Color="#D8E0E8" />
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Ink}" />
    </Style>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="White" />
      <Setter Property="Background" Value="{StaticResource Blue}" />
      <Setter Property="BorderThickness" Value="0" />
      <Setter Property="Padding" Value="18,10" />
      <Setter Property="Margin" Value="0,0,8,0" />
      <Setter Property="FontWeight" Value="SemiBold" />
      <Setter Property="Cursor" Value="Hand" />
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{StaticResource Ink}" />
      <Setter Property="Margin" Value="0,8,0,8" />
      <Setter Property="FontSize" Value="15" />
    </Style>
    <Style TargetType="RadioButton">
      <Setter Property="Foreground" Value="{StaticResource Ink}" />
      <Setter Property="Margin" Value="0,7,0,7" />
      <Setter Property="FontSize" Value="14" />
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="78" />
      <RowDefinition Height="*" />
      <RowDefinition Height="58" />
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="{StaticResource Navy}">
      <Grid Margin="28,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*" />
          <ColumnDefinition Width="Auto" />
        </Grid.ColumnDefinitions>
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="ZiAAS" Foreground="{StaticResource Cyan}" FontSize="20" FontWeight="Bold" />
          <TextBlock Text="WOODSTOCK BASELINING" Foreground="White" FontSize="18" FontWeight="SemiBold" />
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <Ellipse Width="10" Height="10" Fill="{StaticResource Green}" Margin="0,0,8,0" />
          <TextBlock x:Name="HeaderStatus" Text="Ready for preflight" Foreground="#D9E7F2" VerticalAlignment="Center" />
        </StackPanel>
      </Grid>
    </Border>

    <Grid Grid.Row="1" Margin="28,24,28,18">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="330" />
        <ColumnDefinition Width="24" />
        <ColumnDefinition Width="*" />
        <ColumnDefinition Width="24" />
        <ColumnDefinition Width="300" />
      </Grid.ColumnDefinitions>

      <StackPanel Grid.Column="0">
        <TextBlock Text="Deployment workspace" FontSize="25" FontWeight="SemiBold" />
        <TextBlock Text="Choose the target state for this Windows client." Foreground="{StaticResource Muted}" Margin="0,5,0,18" />

        <Border Background="White" BorderBrush="{StaticResource Line}" BorderThickness="1" Padding="20">
          <StackPanel>
            <TextBlock Text="Products" FontSize="16" FontWeight="SemiBold" />
            <TextBlock Text="Selected products are cleaned first, then installed in dependency order." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,4,0,12" />
            <CheckBox x:Name="OfficeCheck" Content="Microsoft 365 Apps for enterprise" IsChecked="True" />
            <TextBlock Text="64-bit | en-GB | Semi-Annual Enterprise requested" FontSize="12" Foreground="{StaticResource Muted}" Margin="24,0,0,7" />
            <CheckBox x:Name="AdobeCheck" Content="Adobe" IsChecked="True" />
            <StackPanel x:Name="AdobeChoices" Margin="24,0,0,6">
              <RadioButton x:Name="ReaderRadio" Content="Acrobat Reader" GroupName="AdobeProduct" IsChecked="True" />
              <RadioButton x:Name="ProRadio" Content="Acrobat Pro" GroupName="AdobeProduct" />
              <TextBlock Text="UK English proof and licensed package required for Pro." FontSize="12" Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="22,0,0,0" />
            </StackPanel>
            <CheckBox x:Name="LeapCheck" Content="LEAP" IsChecked="True" />
            <TextBlock Text="Installed last so Office and Adobe add-ins can bind." FontSize="12" Foreground="{StaticResource Muted}" Margin="24,0,0,0" TextWrapping="Wrap" />
          </StackPanel>
        </Border>
      </StackPanel>

      <StackPanel Grid.Column="2">
        <TextBlock Text="Run sequence" FontSize="19" FontWeight="SemiBold" />
        <TextBlock Text="The preview makes the destructive boundary visible before anything runs." Foreground="{StaticResource Muted}" Margin="0,4,0,12" />
        <Border Background="White" BorderBrush="{StaticResource Line}" BorderThickness="1" Padding="20">
          <StackPanel x:Name="SequencePanel" />
        </Border>

        <Border Background="#EAF6F8" BorderBrush="#B8E4EB" BorderThickness="1" Padding="16" Margin="0,18,0,0">
          <StackPanel>
            <TextBlock Text="Safe operating boundary" FontWeight="SemiBold" Foreground="{StaticResource Blue}" />
            <TextBlock Text="All required installers are staged and verified before cleanup begins. A failed preflight stops the run before changes are made." TextWrapping="Wrap" Foreground="{StaticResource Blue}" Margin="0,5,0,0" />
          </StackPanel>
        </Border>
      </StackPanel>

      <StackPanel Grid.Column="4">
        <TextBlock Text="Preflight" FontSize="19" FontWeight="SemiBold" />
        <TextBlock Text="Readiness checks for the selected run." Foreground="{StaticResource Muted}" Margin="0,4,0,12" />
        <Border Background="White" BorderBrush="{StaticResource Line}" BorderThickness="1" Padding="20">
          <StackPanel x:Name="PreflightPanel">
            <TextBlock Text="Not run" Foreground="{StaticResource Muted}" FontWeight="SemiBold" />
            <TextBlock Text="Run preflight to check elevation, network, disk space, installers, signatures, and blocking applications." TextWrapping="Wrap" Foreground="{StaticResource Muted}" Margin="0,8,0,0" />
          </StackPanel>
        </Border>
        <Border Background="White" BorderBrush="{StaticResource Line}" BorderThickness="1" Padding="20" Margin="0,18,0,0">
          <StackPanel>
            <TextBlock Text="Operator actions" FontSize="16" FontWeight="SemiBold" />
            <Button x:Name="PreflightButton" Content="Run preflight" Margin="0,14,0,8" />
            <Button x:Name="StartButton" Content="Start deployment" Background="{StaticResource Cyan}" IsEnabled="False" />
            <TextBlock Text="Example mode only. No software is changed." Foreground="{StaticResource Muted}" FontSize="12" TextWrapping="Wrap" Margin="0,14,0,0" />
          </StackPanel>
        </Border>
      </StackPanel>
    </Grid>

    <Border Grid.Row="2" Background="White" BorderBrush="{StaticResource Line}" BorderThickness="0,1,0,0">
      <Grid Margin="28,0">
        <TextBlock Text="ZiAAS MSP Toolkit  |  Woodstock Baselining  |  Logs and reports remain available to the engineer" Foreground="{StaticResource Muted}" VerticalAlignment="Center" />
        <TextBlock x:Name="FooterStatus" Text="Simulation preview" Foreground="{StaticResource Muted}" HorizontalAlignment="Right" VerticalAlignment="Center" />
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

function Get-Control([string]$Name) {
    $control = $window.FindName($Name)
    if ($null -eq $control) {
        throw "GUI control was not found: $Name"
    }
    return $control
}

$headerStatus = Get-Control "HeaderStatus"
$footerStatus = Get-Control "FooterStatus"
$officeCheck = Get-Control "OfficeCheck"
$adobeCheck = Get-Control "AdobeCheck"
$leapCheck = Get-Control "LeapCheck"
$readerRadio = Get-Control "ReaderRadio"
$proRadio = Get-Control "ProRadio"
$adobeChoices = Get-Control "AdobeChoices"
$sequencePanel = Get-Control "SequencePanel"
$preflightPanel = Get-Control "PreflightPanel"
$preflightButton = Get-Control "PreflightButton"
$startButton = Get-Control "StartButton"

function New-SequenceRow([string]$Label, [string]$Detail) {
    $grid = New-Object Windows.Controls.Grid
    $grid.Margin = New-Object Windows.Thickness(0, 0, 0, 13)
    $grid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
    $grid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
    $grid.ColumnDefinitions[0].Width = New-Object Windows.GridLength(28)
    $grid.ColumnDefinitions[1].Width = New-Object Windows.GridLength(1, [Windows.GridUnitType]::Star)

    $marker = New-Object Windows.Controls.Border
    $marker.Width = 22
    $marker.Height = 22
    $marker.CornerRadius = New-Object Windows.CornerRadius(11)
    $marker.Background = [Windows.Media.Brushes]::LightGray
    $marker.Child = New-Object Windows.Controls.TextBlock
    $marker.Child.Text = "-"
    $marker.Child.HorizontalAlignment = "Center"
    $marker.Child.VerticalAlignment = "Center"
    $marker.Child.Foreground = [Windows.Media.Brushes]::White
    $marker.Child.FontWeight = "Bold"
    [Windows.Controls.Grid]::SetColumn($marker, 0)
    $grid.Children.Add($marker) | Out-Null

    $stack = New-Object Windows.Controls.StackPanel
    $title = New-Object Windows.Controls.TextBlock
    $title.Text = $Label
    $title.FontWeight = "SemiBold"
    $detailText = New-Object Windows.Controls.TextBlock
    $detailText.Text = $Detail
    $detailText.Foreground = [Windows.Media.Brushes]::Gray
    $detailText.FontSize = 12
    $detailText.Margin = New-Object Windows.Thickness(0, 3, 0, 0)
    $stack.Children.Add($title) | Out-Null
    $stack.Children.Add($detailText) | Out-Null
    [Windows.Controls.Grid]::SetColumn($stack, 1)
    $grid.Children.Add($stack) | Out-Null

    return [pscustomobject]@{ Grid = $grid; Marker = $marker; Title = $title }
}

function Get-SelectedProducts {
    $selected = @()
    if ($officeCheck.IsChecked) { $selected += "Office" }
    if ($adobeCheck.IsChecked) { $selected += $(if ($proRadio.IsChecked) { "Acrobat Pro" } else { "Acrobat Reader" }) }
    if ($leapCheck.IsChecked) { $selected += "LEAP" }
    return $selected
}

function Update-Sequence {
    $sequencePanel.Children.Clear()
    $rows = @()
    $selected = Get-SelectedProducts
    $rows += New-SequenceRow "Preflight" "Confirm admin, network, disk, signatures, and application state"
    if ($leapCheck.IsChecked) { $rows += New-SequenceRow "Remove and clean LEAP" "Preserve approved user data; remove LEAP before dependent apps" }
    if ($adobeCheck.IsChecked) { $rows += New-SequenceRow "Remove and clean Adobe" "Remove Reader/Acrobat and apply safe cleanup" }
    if ($officeCheck.IsChecked) { $rows += New-SequenceRow "Remove and clean Office" "Remove Click-to-Run/MSI remnants within allowlisted boundaries" }
    if ($officeCheck.IsChecked -or $adobeCheck.IsChecked) { $rows += New-SequenceRow "Wait 60 seconds" "Allow installer services and cleanup state to settle" }
    if ($officeCheck.IsChecked) { $rows += New-SequenceRow "Install Office" "Microsoft 365 Apps for enterprise, x64, UK English, enterprise channel" }
    if ($adobeCheck.IsChecked) { $rows += New-SequenceRow "Install Adobe" "Reader or licensed Pro package with UK language proof and New Acrobat policy" }
    if ($leapCheck.IsChecked) { $rows += New-SequenceRow "Install LEAP last" "Install add-ins only after Office and Adobe are complete" }
    $rows += New-SequenceRow "Verify and report" "Write logs, JSON/text report, reboot recommendation, and next action"
    foreach ($row in $rows) { $sequencePanel.Children.Add($row.Grid) | Out-Null }
    $footerStatus.Text = "$(($selected -join ', ')) selected"
    $startButton.IsEnabled = $false
}

function Set-PreflightState([bool]$Passed) {
    $preflightPanel.Children.Clear()
    $headline = New-Object Windows.Controls.TextBlock
    $headline.FontWeight = "SemiBold"
    $headline.Text = if ($Passed) { "Ready to run" } else { "Action required" }
    $headline.Foreground = if ($Passed) { [Windows.Media.Brushes]::ForestGreen } else { [Windows.Media.Brushes]::Firebrick }
    $detail = New-Object Windows.Controls.TextBlock
    $detail.Margin = New-Object Windows.Thickness(0, 8, 0, 0)
    $detail.TextWrapping = "Wrap"
    $detail.Text = if ($Passed) { "All example checks passed. The real app would now enable the destructive deployment action." } else { "The real app would stop here and show the exact failed check and recovery hint." }
    $detail.Foreground = [Windows.Media.Brushes]::Gray
    $preflightPanel.Children.Add($headline) | Out-Null
    $preflightPanel.Children.Add($detail) | Out-Null
    $startButton.IsEnabled = $Passed
}

$officeCheck.Add_Checked({ Update-Sequence })
$officeCheck.Add_Unchecked({ Update-Sequence })
$adobeCheck.Add_Checked({ $adobeChoices.IsEnabled = $true; Update-Sequence })
$adobeCheck.Add_Unchecked({ $adobeChoices.IsEnabled = $false; Update-Sequence })
$leapCheck.Add_Checked({ Update-Sequence })
$leapCheck.Add_Unchecked({ Update-Sequence })
$readerRadio.Add_Checked({ Update-Sequence })
$proRadio.Add_Checked({ Update-Sequence })

$preflightButton.Add_Click({
    $headerStatus.Text = "Preflight passed"
    Set-PreflightState $true
    $footerStatus.Text = "Preflight passed | ready to start"
})

$startButton.Add_Click({
    $startButton.IsEnabled = $false
    $preflightButton.IsEnabled = $false
    $headerStatus.Text = "Example run complete"
    $footerStatus.Text = "Simulation complete | no software changed"
    [Windows.MessageBox]::Show("This branded GUI example completed its simulated flow. The production version would invoke the existing orchestrator here and stream its real step results, logs, and exit code.", "ZiAAS Woodstock Baselining", "OK", "Information") | Out-Null
})

Update-Sequence
[void]$window.ShowDialog()
