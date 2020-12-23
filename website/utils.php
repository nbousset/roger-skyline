<?php
function error($redirect, $msg)
{
	header('Location: ' . $redirect . '?error=' . $msg);
	exit();
}
?>
