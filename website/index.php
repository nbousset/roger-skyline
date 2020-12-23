<!DOCTYPE html>

<?php

session_start();

if (isset($_SESSION['email']))
{
	?>
	<html>
		<div align="center">
			<a href="signout.php">SIGN OUT</a><br>
		<div/>
	</html>
	<?php
}
else
{
	?>
	<html>
		<div align="center">
			<a href="signupform.php">SIGN UP</a><br>
			<a href="signinform.php">SIGN IN</a><br>
		<div/>
	</html>
	<?php
}

?>
